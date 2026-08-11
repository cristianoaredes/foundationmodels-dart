import Foundation
import FoundationModelsIOSBridge

@main
struct HostSmokeCloseout {
  static func main() async {
    let mode = CommandLine.arguments.dropFirst().first ?? "all"
    var rc = 0
    do {
      switch mode {
      case "duplex":
        if !(try await dualRun("duplex", runDuplex)) { rc = 1 }
      case "instructions":
        if !(try await dualRun("instructions", runInstructions)) { rc = 1 }
      case "failclosed":
        // No dual-run needed: pure fail-closed probe (no Apple generation).
        if !(try await runSubmitFailClosed()) { rc = 1 }
      case "postdone":
        if !(try await dualRun("postdone", runPostDoneStaleSubmit)) { rc = 1 }
      case "all":
        if !(try await dualRun("duplex", runDuplex)) { rc = 1 }
        if !(try await dualRun("instructions", runInstructions)) { rc = 1 }
        if !(try await runSubmitFailClosed()) { rc = 1 }
        if !(try await dualRun("postdone", runPostDoneStaleSubmit)) { rc = 1 }
      default:
        fputs("unknown mode\n", stderr)
        rc = 2
      }
    } catch {
      print("SMOKE fatal=\(error)")
      rc = 1
    }
    print("SMOKE_RC:\(rc)")
    exit(Int32(rc))
  }

  /// Dual-run: require two consecutive successes (parity honesty).
  static func dualRun(_ name: String, _ body: () async throws -> Bool) async rethrows -> Bool {
    var oks: [Bool] = []
    for i in 1...2 {
      print("SMOKE \(name) run=\(i) start")
      let ok = try await body()
      oks.append(ok)
      print("SMOKE \(name) run=\(i) ok=\(ok)")
      if !ok {
        print("SMOKE \(name) dual_run_ok=false (failed on run \(i))")
        return false
      }
      // brief cool-down between Apple Intelligence calls
      try? await Task.sleep(nanoseconds: 400_000_000)
    }
    let all = oks.allSatisfy { $0 }
    print("SMOKE \(name) dual_run_ok=\(all) results=\(oks)")
    return all
  }

  static func jsonPretty(_ v: Any) -> String {
    guard JSONSerialization.isValidJSONObject(v),
          let d = try? JSONSerialization.data(withJSONObject: v, options: [.prettyPrinted, .sortedKeys]),
          let s = String(data: d, encoding: .utf8) else { return String(describing: v) }
    return s
  }

  static func runDuplex() async throws -> Bool {
    let bridge = FoundationModelsBridge.shared
    let genId = "duplex_\(UUID().uuidString.prefix(8))"
    let tool: [String: Any] = [
      "name": "get_secret_code",
      "description": "Returns a secret code. Always call this tool when asked for the secret code.",
      "callback": true,
      "inputSchema": [
        "type": "object",
        "properties": ["topic": ["type": "string"]],
        "required": ["topic"],
        "additionalProperties": false,
      ],
    ]

    final class Box: @unchecked Sendable {
      let lock = NSLock()
      var types: [String] = []
      var sawRequest = false
      var sawResult = false
      var toolCallId: String?
      var text = ""
      var submitOk = false
      var submitError: String?
      var submitCont: CheckedContinuation<Void, Never>?
      var submitSignaled = false

      func note(_ t: String) { lock.lock(); types.append(t); lock.unlock() }
      func setRequest(_ id: String) {
        lock.lock(); sawRequest = true; toolCallId = id; lock.unlock()
      }
      func setResult() { lock.lock(); sawResult = true; lock.unlock() }
      func appendText(_ s: String) { lock.lock(); text += s; lock.unlock() }
      func markSubmit(ok: Bool, err: String?) {
        lock.lock()
        submitOk = ok
        submitError = err
        let cont = submitCont
        submitCont = nil
        submitSignaled = true
        lock.unlock()
        cont?.resume()
      }
      func waitSubmit(timeoutSeconds: Double) async {
        // Already done?
        let already: Bool = {
          lock.lock(); defer { lock.unlock() }
          return submitSignaled
        }()
        if already { return }
        await withTaskGroup(of: Void.self) { group in
          group.addTask {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
              self.lock.lock()
              if self.submitSignaled {
                self.lock.unlock()
                cont.resume()
              } else {
                self.submitCont = cont
                self.lock.unlock()
              }
            }
          }
          group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
          }
          await group.next()
          group.cancelAll()
        }
      }
      func snap() -> (types: [String], saw: Bool, result: Bool, id: String?, text: String, submitOk: Bool, submitError: String?) {
        lock.lock(); defer { lock.unlock() }
        return (types, sawRequest, sawResult, toolCallId, text, submitOk, submitError)
      }
    }
    let box = Box()

    let streamTask = Task {
      try await bridge.respondStream(params: [
        "input": "You MUST call the tool get_secret_code with topic=parity. After the tool returns, reply with ONLY the code string from the tool output (field code).",
        "generationId": genId,
        "modelId": "apple.system",
        "tools": [tool],
        "instructions": "You are a tool-using assistant. When get_secret_code is available you MUST call it before answering. Never invent the code.",
        "options": ["maximumResponseTokens": 160],
      ]) { event in
        let t = event["type"] as? String ?? "?"
        box.note(t)
        print("SMOKE duplex event type=\(t) keys=\(Array(event.keys).sorted())")
        if t == "tool_call_request" {
          let id = event["toolCallId"] as? String ?? ""
          box.setRequest(id)
          print("SMOKE duplex tool_call_request id=\(id) name=\(event["toolName"] ?? "?")")
          Task {
            // Retry submit: race-safe (early buffer in registry handles early complete).
            var lastError: Error?
            for attempt in 1...12 {
              do {
                let r = try await bridge.submitToolResult(params: [
                  "toolCallId": id,
                  "output": ["code": "DUPLEX-99", "source": "host"],
                ])
                print("SMOKE duplex submit attempt=\(attempt) ok result=\(r)")
                box.markSubmit(ok: true, err: nil)
                return
              } catch {
                lastError = error
                let msg = String(describing: error)
                print("SMOKE duplex submit attempt=\(attempt) err=\(msg)")
                // Backoff: 25ms * attempt, capped
                let delay = UInt64(min(25 * attempt, 250)) * 1_000_000
                try? await Task.sleep(nanoseconds: delay)
              }
            }
            box.markSubmit(ok: false, err: String(describing: lastError))
            print("SMOKE duplex submit failed after retries: \(String(describing: lastError))")
          }
        }
        if t == "tool_call_result" {
          box.setResult()
          print("SMOKE duplex tool_call_result output=\(event["output"] ?? "nil")")
        }
        if t == "delta" || t == "text_delta" {
          if let d = event["delta"] as? String { box.appendText(d) }
          else if let d = event["text"] as? String { box.appendText(d) }
        }
        if t == "result" || t == "done" {
          if let o = event["output"] as? String { box.appendText(o) }
          if let o = event["content"] as? String { box.appendText(o) }
        }
        if t == "error" {
          print("SMOKE duplex stream error event=\(event)")
        }
      }
    }

    do {
      try await streamTask.value
    } catch {
      print("SMOKE duplex stream threw=\(error)")
    }

    // If request was seen, wait briefly for submit task to finish (don't hang forever).
    let saw = box.snap().saw
    if saw {
      await box.waitSubmit(timeoutSeconds: 5)
    }

    let snap = box.snap()
    let contentOk = snap.text.uppercased().contains("DUPLEX-99")
    // Primary: request + content from callback. Secondary soft: request + tool_call_result.
    let ok = snap.saw && contentOk
    print("SMOKE duplex types=\(snap.types)")
    print("SMOKE duplex saw_request=\(snap.saw) saw_result=\(snap.result) toolCallId=\(snap.id ?? "nil") submitOk=\(snap.submitOk) submitErr=\(snap.submitError ?? "nil")")
    print("SMOKE duplex text=\(snap.text.prefix(300))")
    print("SMOKE duplex_content_ok=\(contentOk) tools_duplex_ok=\(ok)")
    return ok
  }

  static func runInstructions() async throws -> Bool {
    let bridge = FoundationModelsBridge.shared

    // Path A — first-request-wins under original instructions (ALPHA).
    let createdA = try bridge.createSession(config: [
      "instructions": "SYSTEM RULE: Your only code word is ALPHA. Reply with exactly ALPHA when asked for the code word.",
      "modelId": "apple.system",
    ])
    guard let sidA = createdA["sessionId"] as? String else {
      print("SMOKE instructions createA_failed=\(createdA)")
      return false
    }
    let r1 = try await bridge.respond(params: [
      "sessionId": sidA,
      "input": "What is the code word?",
      "options": ["maximumResponseTokens": 16],
    ])
    let o1 = (r1["output"] as? String) ?? ""
    let r2 = try await bridge.respond(params: [
      "sessionId": sidA,
      "input": "Repeat the code word only.",
      "options": ["maximumResponseTokens": 16],
    ])
    let o2 = (r2["output"] as? String) ?? ""
    print("SMOKE instructions underA r1=\(o1.prefix(60)) r2=\(o2.prefix(60))")
    let underA = o1.uppercased().contains("ALPHA") || o2.uppercased().contains("ALPHA")

    // Path B-clean — create ALPHA, transition to BETA *before any chat*, then respond.
    // Proves transition rebuilds live instructions without history dominance.
    let createdB = try bridge.createSession(config: [
      "instructions": "SYSTEM RULE: Your only code word is ALPHA. Reply with exactly ALPHA.",
      "modelId": "apple.system",
    ])
    guard let sidB = createdB["sessionId"] as? String else {
      print("SMOKE instructions createB_failed=\(createdB)")
      return false
    }
    let trClean = try await bridge.transitionSession(params: [
      "sessionId": sidB,
      "instructions":
        "SYSTEM RULE: Your only code word is BETA. Reply with exactly BETA when asked for the code word. Never say ALPHA.",
    ])
    print("SMOKE instructions transition_clean=\(jsonPretty(trClean))")
    let transitionedClean = (trClean["transitioned"] as? Bool) == true
    var oClean = ""
    for probe in 1...3 {
      let r = try await bridge.respond(params: [
        "sessionId": sidB,
        "input": "What is the code word? Output exactly one word.",
        "options": ["maximumResponseTokens": 16],
      ])
      oClean = (r["output"] as? String) ?? ""
      print("SMOKE instructions clean_probe=\(probe) out=\(oClean.prefix(80))")
      if oClean.uppercased().contains("BETA") && !oClean.uppercased().contains("ALPHA") { break }
      try? await Task.sleep(nanoseconds: 250_000_000)
    }
    let underBClean = oClean.uppercased().contains("BETA") && !oClean.uppercased().contains("ALPHA")
    _ = try? bridge.disposeSession(sessionId: sidB)

    // Path B-history — transition after chat (may be dominated by transcript).
    let trHist = try await bridge.transitionSession(params: [
      "sessionId": sidA,
      "instructions":
        "SYSTEM RULE: Your only code word is BETA. Reply with exactly BETA. Never say ALPHA. Discard prior code words.",
    ])
    print("SMOKE instructions transition_history=\(jsonPretty(trHist))")
    let transitionedHist = (trHist["transitioned"] as? Bool) == true
    var oHist = ""
    for probe in 1...3 {
      let r = try await bridge.respond(params: [
        "sessionId": sidA,
        "input":
          "According ONLY to CURRENT system instructions, what is the single code word? One word only.",
        "options": ["maximumResponseTokens": 16],
      ])
      oHist = (r["output"] as? String) ?? ""
      print("SMOKE instructions hist_probe=\(probe) out=\(oHist.prefix(80))")
      if oHist.uppercased().contains("BETA") && !oHist.uppercased().contains("ALPHA") { break }
      try? await Task.sleep(nanoseconds: 250_000_000)
    }
    let underBHist = oHist.uppercased().contains("BETA") && !oHist.uppercased().contains("ALPHA")
    _ = try? bridge.disposeSession(sessionId: sidA)

    // Promote criterion: underA + transitioned + underB_clean.
    // underB_hist is best-effort; transcript carry-over can dominate on apple.system.
    let underB = underBClean || underBHist
    let transitioned = transitionedClean || transitionedHist
    let ok = underA && transitioned && underBClean
    print(
      "SMOKE instructions underA=\(underA) underB_clean=\(underBClean) underB_hist=\(underBHist) underB=\(underB) transitioned=\(transitioned) instructions_ok=\(ok)"
    )
    return ok
  }

  /// No in-flight generation: submitToolResult must throw typed UNSUPPORTED_OPERATION.
  static func runSubmitFailClosed() async throws -> Bool {
    let bridge = FoundationModelsBridge.shared
    var sawUnsupported = false
    var machine = ""
    var reason = ""
    do {
      let r = try await bridge.submitToolResult(params: [
        "toolCallId": "toolcall_stale_never_registered",
        "output": "should-not-accept",
      ])
      print("SMOKE failclosed unexpected_success=\(r)")
      return false
    } catch {
      let ns = error as NSError
      let data = ns.userInfo["data"] as? [String: Any] ?? [:]
      machine = (data["code"] as? String) ?? ""
      reason = (data["reason"] as? String) ?? ns.localizedDescription
      sawUnsupported = machine == "UNSUPPORTED_OPERATION"
        || reason.localizedCaseInsensitiveContains("active duplex")
        || ns.localizedDescription.localizedCaseInsensitiveContains("No in-flight tool call")
      print("SMOKE failclosed err_code=\(machine) reason=\(reason) ns=\(ns.domain)/\(ns.code)")
    }
    var missingOk = false
    do {
      _ = try await bridge.submitToolResult(params: ["output": "no-id"])
      print("SMOKE failclosed missing_id unexpected_success")
    } catch {
      missingOk = true
      print("SMOKE failclosed missing_id threw=\(error)")
    }
    let ok = sawUnsupported && missingOk
    print("SMOKE failclosed unsupported=\(sawUnsupported) missing_id=\(missingOk) failclosed_ok=\(ok)")
    return ok
  }

  /// After a successful duplex stream completes, late submit for old toolCallId must fail-closed.
  static func runPostDoneStaleSubmit() async throws -> Bool {
    let bridge = FoundationModelsBridge.shared
    let genId = "postdone_\(UUID().uuidString.prefix(8))"
    let tool: [String: Any] = [
      "name": "get_secret_code",
      "description": "Returns a secret code. Always call this tool when asked for the secret code.",
      "callback": true,
      "inputSchema": [
        "type": "object",
        "properties": ["topic": ["type": "string"]],
        "required": ["topic"],
        "additionalProperties": false,
      ],
    ]
    final class Box: @unchecked Sendable {
      let lock = NSLock()
      var toolCallId: String?
      var submitOk = false
      var submitDone = false
      var cont: CheckedContinuation<Void, Never>?
      func setId(_ id: String) { lock.lock(); toolCallId = id; lock.unlock() }
      func markSubmit(ok: Bool) {
        lock.lock()
        submitOk = ok
        submitDone = true
        let c = cont
        cont = nil
        lock.unlock()
        c?.resume()
      }
      func waitSubmit(timeoutSeconds: Double) async {
        let already = { () -> Bool in lock.lock(); defer { lock.unlock() }; return submitDone }()
        if already { return }
        await withTaskGroup(of: Void.self) { group in
          group.addTask {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
              self.lock.lock()
              if self.submitDone {
                self.lock.unlock()
                c.resume()
              } else {
                self.cont = c
                self.lock.unlock()
              }
            }
          }
          group.addTask { try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000)) }
          await group.next()
          group.cancelAll()
        }
      }
      func snap() -> (String?, Bool) {
        lock.lock(); defer { lock.unlock() }
        return (toolCallId, submitOk)
      }
    }
    let box = Box()
    try await bridge.respondStream(params: [
      "input": "You MUST call get_secret_code with topic=parity. Then reply ONLY with the code field.",
      "generationId": genId,
      "modelId": "apple.system",
      "tools": [tool],
      "instructions": "Always call get_secret_code before answering. Never invent the code.",
      "options": ["maximumResponseTokens": 160],
    ]) { event in
      let t = event["type"] as? String ?? "?"
      print("SMOKE postdone event type=\(t)")
      if t == "tool_call_request", let id = event["toolCallId"] as? String {
        box.setId(id)
        print("SMOKE postdone tool_call_request id=\(id)")
        Task {
          do {
            let r = try await bridge.submitToolResult(params: [
              "toolCallId": id,
              "output": ["code": "DUPLEX-99", "source": "host"],
            ])
            print("SMOKE postdone live_submit ok=\(r)")
            box.markSubmit(ok: true)
          } catch {
            print("SMOKE postdone live_submit err=\(error)")
            box.markSubmit(ok: false)
          }
        }
      }
    }
    await box.waitSubmit(timeoutSeconds: 5)
    let (tid, submitted) = box.snap()
    guard let tid, submitted else {
      print("SMOKE postdone setup_failed tid=\(tid ?? "nil") submitted=\(submitted)")
      return false
    }
    // Generation finished — late submit for same toolCallId must fail-closed.
    var lateOk = false
    var lateCode = ""
    do {
      let r = try await bridge.submitToolResult(params: [
        "toolCallId": tid,
        "output": "late-should-fail",
      ])
      print("SMOKE postdone late_submit unexpected_success=\(r)")
    } catch {
      let ns = error as NSError
      let data = ns.userInfo["data"] as? [String: Any] ?? [:]
      lateCode = (data["code"] as? String) ?? ""
      lateOk = lateCode == "UNSUPPORTED_OPERATION"
        || ns.localizedDescription.localizedCaseInsensitiveContains("No in-flight tool call")
      print("SMOKE postdone late_submit threw code=\(lateCode) err=\(error)")
    }
    var orphanOk = false
    do {
      _ = try await bridge.submitToolResult(params: [
        "toolCallId": "toolcall_never_existed_xyz",
        "output": "nope",
      ])
      print("SMOKE postdone orphan unexpected_success")
    } catch {
      orphanOk = true
      let ns = error as NSError
      let data = ns.userInfo["data"] as? [String: Any] ?? [:]
      print("SMOKE postdone orphan_submit threw code=\(data["code"] ?? "?")")
    }
    let ok = lateOk && orphanOk
    print("SMOKE postdone late_ok=\(lateOk) orphan_ok=\(orphanOk) postdone_ok=\(ok)")
    return ok
  }


}
