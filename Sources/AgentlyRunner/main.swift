import ArgumentParser
import ApplicationServices
import Foundation
import Logging
import UIGraph
import Skills

// Audio feedback functions
func playFailureChime() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    process.arguments = ["/System/Library/Sounds/Basso.aiff"]
    try? process.run()
}

func playCompletionChime() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    process.arguments = ["/System/Library/Sounds/Glass.aiff"]
    try? process.run()
}

// Verification result structure
struct VerificationResult {
    let success: Bool
    let confidence: Double
    let reasoning: String
    let shouldRetry: Bool
    let retryReason: String
    let screenshotPath: String?
    let uiGraphPath: String?
    let planUpdate: [String: Any]? // Added for verifier insights
}

@main
struct AgentlyRunner: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agently",
        abstract: "Agently - AI agent for macOS automation via accessibility APIs",
        version: "0.1.0"
    )
    
    @Option(name: .shortAndLong, help: "Task to execute")
    var task: String?
    
    @Option(name: .shortAndLong, help: "Output format (json, text)")
    var format: OutputFormat = .text
    
    @Flag(name: .long, help: "Build UI graph only, don't execute")
    var graphOnly = false
    
    @Flag(name: .long, help: "Enable verbose logging")
    var verbose = false
    
    @Flag(name: .long, help: "Run accessibility permission preflight check")
    var preflight = false
    
    @Flag(name: .long, help: "Enable detailed LLM conversation logging (may slow down execution)")
    var enableLlmLogging = false
    
    func run() async throws {
        setupLogging()
        
        if preflight {
            try await runPreflightCheck()
            return
        }
        
        if graphOnly {
            try await buildAndOutputGraph()
            return
        }
        
        guard let task = task else {
            throw ValidationError("Task is required unless using --graph-only or --preflight")
        }
        
        try await executeTask(task)
    }
    
    private func setupLogging() {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = verbose ? .debug : .info
            return handler
        }
    }
    
    private func runPreflightCheck() async throws {
        let logger = Logger(label: "PreflightCheck")
        logger.info("Running accessibility preflight check...")
        
        // Check accessibility permissions
        let trusted = AXIsProcessTrusted()
        
        if trusted {
            logger.info("✅ Accessibility permissions granted")
        } else {
            logger.warning("❌ Accessibility permissions not granted")
            logger.info("Please grant accessibility access in System Settings > Privacy & Security > Accessibility")
            
            // Try to trigger permission prompt
            let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
            let _ = AXIsProcessTrustedWithOptions(options)
        }
        
        // Test basic graph building
        do {
            let graphBuilder = AccessibilityGraphBuilder()
            let graph = try graphBuilder.buildGraph()
            logger.info("✅ Successfully built UI graph with \(graph.elements.count) elements")
        } catch {
            logger.error("❌ Failed to build UI graph: \(error)")
            throw error
        }
        
        logger.info("Preflight check complete")
    }
    
    private func buildAndOutputGraph() async throws {
        let logger = Logger(label: "GraphBuilder")
        logger.info("Building UI accessibility graph...")
        
        let graphBuilder = AccessibilityGraphBuilder()
        let graph = try graphBuilder.buildGraph()
        
        // Always save to standalone graphs directory for --graph-only mode
        let standaloneDir = URL(fileURLWithPath: "logs/standalone_graphs")
        try FileManager.default.createDirectory(at: standaloneDir, withIntermediateDirectories: true)
        
        let timestamp = Int(Date().timeIntervalSince1970)
        let runLogger = RunLogger()
        try runLogger.saveGraphToFile(graph, filename: "accessibility_graph_\(timestamp)", directory: standaloneDir)
        
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            
            let data = try encoder.encode(graph)
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
            
        case .text:
            let runLogger = RunLogger()
            runLogger.printGraphSummary(graph)
        }
    }
    
    private func executeTask(_ taskDescription: String) async throws {
        let logger = Logger(label: "TaskExecution")
        logger.info("Executing task: \(taskDescription)")
        
        let runLogger = RunLogger()
        
        // Create run directory
        let runDir = try runLogger.createRunDirectory(task: taskDescription)
        logger.info("Created run directory: \(runDir.path)")
        
        // 1. Build initial UI graph
        let graphBuilder = AccessibilityGraphBuilder()
        let initialGraph = try graphBuilder.buildGraph()
        logger.info("Built initial graph with \(initialGraph.elements.count) elements")
        
        // Save initial graph for inspection
        try runLogger.saveGraphToRunDirectory(initialGraph, filename: "00_initial_graph", runDir: runDir)
        
        // 2. Call Python planner to generate action plan
        let plannerResult = try await callPythonPlanner(task: taskDescription, graph: initialGraph, runDir: runDir)
        
        guard let actions = plannerResult["actions"] as? [[String: Any]] else {
            throw AgentlyError.planningFailed("No actions generated by planner")
        }
        
        logger.info("Generated plan with \(actions.count) actions")
        
        // 3. Execute actions with retry mechanism
        let skillExecutor = SkillExecutor()
        var currentGraph = initialGraph
        var executedActions: [SkillResult] = []
        var consecutiveFailures = 0
        let maxConsecutiveFailures = 3
        
        for (index, actionData) in actions.enumerated() {
            logger.info("Executing action \(index + 1)/\(actions.count)")
            
            do {
                let action = parseAction(from: actionData)
                let result = skillExecutor.execute(action, in: currentGraph)
                executedActions.append(result)
                
                if !result.success {
                    logger.error("Action failed: \(result.errorMessage ?? "unknown error")")
                    consecutiveFailures += 1
                    
                    if consecutiveFailures >= maxConsecutiveFailures {
                        logger.error("❌ Task execution failed after \(maxConsecutiveFailures) consecutive failures")
                        playFailureChime()
                        throw AgentlyError.executionFailed("Task failed after \(maxConsecutiveFailures) consecutive failures")
                    }
                    
                    // Play failure chime
                    playFailureChime()
                    
                    // Try to recover with plan regeneration
                    logger.info("🔄 Regenerating plan from current state...")
                    currentGraph = try graphBuilder.buildGraph()
                    
                    // Save recovery graph for inspection
                    try runLogger.saveGraphToRunDirectory(currentGraph, filename: "recovery_after_action_\(index + 1)", runDir: runDir)
                    
                    let recoveryPlan = try await callPythonPlannerForRecovery(
                        task: taskDescription,
                        graph: currentGraph,
                        failedAction: actionData,
                        error: result.errorMessage ?? "unknown error",
                        completedActions: executedActions,
                        runDir: runDir
                    )
                    
                    // Continue with recovery actions if available
                    if let recoveryActions = recoveryPlan["actions"] as? [[String: Any]], !recoveryActions.isEmpty {
                        logger.info("Attempting recovery with \(recoveryActions.count) actions")
                        
                        // Execute recovery actions
                        var recoverySuccessful = true
                        for (recoveryIndex, recoveryActionData) in recoveryActions.enumerated() {
                            logger.info("Executing recovery action \(recoveryIndex + 1)/\(recoveryActions.count)")
                            
                            do {
                                let recoveryAction = parseActionWithElementResolution(from: recoveryActionData, in: currentGraph)
                                let recoveryResult = skillExecutor.execute(recoveryAction, in: currentGraph)
                                executedActions.append(recoveryResult)
                                
                                if !recoveryResult.success {
                                    logger.error("Recovery action failed: \(recoveryResult.errorMessage ?? "unknown error")")
                                    recoverySuccessful = false
                                    break
                                }
                                
                                // Update graph after successful recovery action
                                if recoveryResult.success {
                                    try await Task.sleep(for: .milliseconds(500))
                                    currentGraph = try graphBuilder.buildGraph()
                                    
                                    // Save recovery progress
                                    try runLogger.saveGraphToRunDirectory(currentGraph, filename: "recovery_step_\(recoveryIndex + 1)", runDir: runDir)
                                }
                            } catch {
                                logger.error("Recovery action execution failed: \(error)")
                                recoverySuccessful = false
                                break
                            }
                        }
                        
                        // If recovery failed, increment failure count
                        if !recoverySuccessful {
                            consecutiveFailures += 1
                            if consecutiveFailures >= maxConsecutiveFailures {
                                logger.error("❌ Task execution failed after \(maxConsecutiveFailures) consecutive failures")
                                playFailureChime()
                                throw AgentlyError.executionFailed("Task failed after \(maxConsecutiveFailures) consecutive failures")
                            }
                            logger.error("Recovery failed, will retry with new plan")
                            continue // Retry the same action with a new plan
                        }
                        
                        logger.info("Recovery completed successfully")
                        consecutiveFailures = 0 // Reset failure count on successful recovery
                    } else {
                        logger.error("No recovery plan available, will retry with new plan")
                        consecutiveFailures += 1
                        if consecutiveFailures >= maxConsecutiveFailures {
                            logger.error("❌ Task execution failed after \(maxConsecutiveFailures) consecutive failures")
                            playFailureChime()
                            throw AgentlyError.executionFailed("Task failed after \(maxConsecutiveFailures) consecutive failures")
                        }
                        continue // Retry the same action with a new plan
                    }
                }
                
                // Update graph after successful action
                if result.success {
                    // Small delay to let UI settle
                    try await Task.sleep(for: .milliseconds(500))
                    currentGraph = try graphBuilder.buildGraph()
                    
                    // Save graph after each action for inspection
                    try runLogger.saveGraphToRunDirectory(currentGraph, filename: "\(String(format: "%02d", index + 1))_after_\(action.type.rawValue)", runDir: runDir)
                    
                    // Verify the step was completed successfully
                    let verificationStartTime = Date()
                    logger.info("🕐 Starting verification at \(verificationStartTime)")
                    
                    let verificationResult = try await verifyStep(
                        stepDescription: action.description,
                        actionType: action.type.rawValue,
                        actionDescription: action.description,
                        runDir: runDir,
                        userTask: taskDescription,
                        completedActions: executedActions.map { $0.action.description }
                    )
                    
                    let verificationEndTime = Date()
                    let verificationDuration = verificationEndTime.timeIntervalSince(verificationStartTime)
                    logger.info("🕐 Verification completed in \(String(format: "%.2f", verificationDuration))s")
                    
                    // Always process plan update suggestions from verifier, regardless of success/failure
                    if let planUpdate = verificationResult.planUpdate {
                        logger.info("📋 Plan update suggestions available from verifier")
                        logger.info("Plan update: \(planUpdate)")
                        
                        // Log the suggested actions specifically
                        if let suggestedActions = planUpdate["suggested_next_actions"] as? [[String: Any]] {
                            logger.info("🎯 Found \(suggestedActions.count) suggested actions:")
                            for (i, action) in suggestedActions.enumerated() {
                                logger.info("  \(i+1). \(action)")
                            }
                        } else {
                            logger.warning("❌ No suggested_next_actions found in plan update")
                        }
                        
                        // Execute suggested actions if available
                        if let suggestedActions = planUpdate["suggested_next_actions"] as? [[String: Any]], !suggestedActions.isEmpty {
                            logger.info("🔄 Using verifier-suggested actions: \(suggestedActions.count) actions")
                            
                            // Execute suggested actions
                            var recoverySuccessful = true
                            for (recoveryIndex, suggestedActionData) in suggestedActions.enumerated() {
                                logger.info("Executing suggested action \(recoveryIndex + 1)/\(suggestedActions.count)")
                                
                                do {
                                    logger.info("Parsing suggested action: \(suggestedActionData)")
                                    // Convert verifier action format to planner action format
                                    var actionData = suggestedActionData
                                    if let actionType = actionData["action"] as? String {
                                        actionData["type"] = actionType
                                        actionData.removeValue(forKey: "action")
                                    }
                                    
                                    let suggestedAction = parseActionWithElementResolution(from: actionData, in: currentGraph)
                                    logger.info("Executing suggested action: \(suggestedAction.description)")
                                    let suggestedResult = skillExecutor.execute(suggestedAction, in: currentGraph)
                                    executedActions.append(suggestedResult)
                                    
                                    if !suggestedResult.success {
                                        logger.error("Suggested action failed: \(suggestedResult.errorMessage ?? "unknown error")")
                                        recoverySuccessful = false
                                        break
                                    }
                                    
                                    // Update graph after successful suggested action
                                    if suggestedResult.success {
                                        try await Task.sleep(for: .milliseconds(500))
                                        currentGraph = try graphBuilder.buildGraph()
                                        
                                        // Save suggested action progress
                                        try runLogger.saveGraphToRunDirectory(currentGraph, filename: "suggested_step_\(recoveryIndex + 1)", runDir: runDir)
                                    }
                                } catch {
                                    logger.error("Suggested action execution failed: \(error)")
                                    recoverySuccessful = false
                                    break
                                }
                            }
                            
                            if recoverySuccessful {
                                logger.info("✅ Suggested actions completed successfully")
                                consecutiveFailures = 0 // Reset failure count on successful recovery
                            } else {
                                logger.warning("Suggested actions failed")
                            }
                        }
                        
                        // Check if task is completed based on verifier analysis
                        if let taskCompleted = planUpdate["task_completed"] as? Bool, taskCompleted {
                            let completionConfidence = planUpdate["completion_confidence"] as? Double ?? 0.0
                            logger.info("🎉 Task completed! Confidence: \(completionConfidence)")
                            logger.info("Current progress: \(planUpdate["current_progress"] as? String ?? "Unknown")")
                            
                            // Play completion chime
                            playCompletionChime()
                            
                            // Save execution summary and results
                            try runLogger.saveExecutionResults(
                                task: taskDescription,
                                executedActions: executedActions,
                                runDir: runDir
                            )
                            
                            // Output results
                            let successCount = executedActions.filter { $0.success }.count
                            logger.info("✅ Task execution completed successfully: \(successCount)/\(executedActions.count) actions successful")
                            
                            return // Exit the function, ending task execution
                        }
                    }
                    
                    // Handle verification failure if step didn't succeed
                    if !verificationResult.success {
                        logger.warning("Step verification failed: \(verificationResult.reasoning)")
                        consecutiveFailures += 1
                        
                        if consecutiveFailures >= maxConsecutiveFailures {
                            logger.error("❌ Task execution failed after \(maxConsecutiveFailures) consecutive verification failures")
                            playFailureChime()
                            throw AgentlyError.executionFailed("Task failed after \(maxConsecutiveFailures) consecutive verification failures")
                        }
                        
                        if verificationResult.shouldRetry {
                            logger.info("Step should be retried: \(verificationResult.retryReason)")
                            
                            // Play failure chime
                            playFailureChime()
                            
                            // Fall back to planner recovery if no suggestions or suggestions failed
                            logger.info("🔄 Regenerating plan from current state after verification failure...")
                            let recoveryPlan = try await callPythonPlannerForRecovery(
                                task: taskDescription,
                                graph: currentGraph,
                                failedAction: actionData,
                                error: "Step verification failed: \(verificationResult.reasoning)",
                                completedActions: executedActions,
                                runDir: runDir
                            )
                            
                            // Continue with recovery actions if available
                            if let recoveryActions = recoveryPlan["actions"] as? [[String: Any]], !recoveryActions.isEmpty {
                                logger.info("Attempting recovery with \(recoveryActions.count) actions")
                                
                                // Execute recovery actions
                                var recoverySuccessful = true
                                for (recoveryIndex, recoveryActionData) in recoveryActions.enumerated() {
                                    logger.info("Executing recovery action \(recoveryIndex + 1)/\(recoveryActions.count)")
                                    
                                    do {
                                        let recoveryAction = parseActionWithElementResolution(from: recoveryActionData, in: currentGraph)
                                        let recoveryResult = skillExecutor.execute(recoveryAction, in: currentGraph)
                                        executedActions.append(recoveryResult)
                                        
                                        if !recoveryResult.success {
                                            logger.error("Recovery action failed: \(recoveryResult.errorMessage ?? "unknown error")")
                                            recoverySuccessful = false
                                            break
                                        }
                                        
                                        // Update graph after successful recovery action
                                        if recoveryResult.success {
                                            try await Task.sleep(for: .milliseconds(500))
                                            currentGraph = try graphBuilder.buildGraph()
                                            
                                            // Save recovery progress
                                            try runLogger.saveGraphToRunDirectory(currentGraph, filename: "recovery_step_\(recoveryIndex + 1)", runDir: runDir)
                                        }
                                    } catch {
                                        logger.error("Recovery action execution failed: \(error)")
                                        recoverySuccessful = false
                                        break
                                    }
                                }
                                
                                // If recovery failed, continue to next iteration (will retry)
                                if !recoverySuccessful {
                                    logger.error("Recovery failed, will retry with new plan")
                                    continue // Retry the same action with a new plan
                                }
                                
                                logger.info("Recovery completed successfully")
                                consecutiveFailures = 0 // Reset failure count on successful recovery
                            } else {
                                logger.error("No recovery plan available, will retry with new plan")
                                continue // Retry the same action with a new plan
                            }
                        } else {
                            logger.warning("Step verification inconclusive, continuing: \(verificationResult.retryReason)")
                            consecutiveFailures = 0 // Reset failure count for inconclusive results
                        }
                    } else {
                        logger.info("Step verified successfully with confidence: \(verificationResult.confidence)")
                        consecutiveFailures = 0 // Reset failure count on successful verification
                    }
                }
                
            } catch {
                logger.error("Failed to execute action: \(error)")
                consecutiveFailures += 1
                if consecutiveFailures >= maxConsecutiveFailures {
                    logger.error("❌ Task execution failed after \(maxConsecutiveFailures) consecutive failures")
                    playFailureChime()
                    throw AgentlyError.executionFailed("Task failed after \(maxConsecutiveFailures) consecutive failures")
                }
                break
            }
        }
        
        // Save execution summary and results
        try runLogger.saveExecutionResults(
            task: taskDescription,
            executedActions: executedActions,
            runDir: runDir
        )
        
        // Output results
        let successCount = executedActions.filter { $0.success }.count
        logger.info("Task execution complete: \(successCount)/\(executedActions.count) actions successful")
        
        if format == .json {
            let results: [String: Any] = [
                "task": taskDescription,
                "total_actions": executedActions.count,
                "successful_actions": successCount,
                "execution_time": executedActions.reduce(0) { $0 + $1.executionTime },
                "actions": executedActions.map { result in
                    [
                        "type": result.action.type.rawValue,
                        "description": result.action.description,
                        "success": result.success,
                        "execution_time": result.executionTime,
                        "error": result.errorMessage as Any
                    ]
                }
            ]
            
            let data = try JSONSerialization.data(withJSONObject: results, options: .prettyPrinted)
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        }
    }
    

    

    

    
    private func callPythonPlanner(task: String, graph: UIGraph, runDir: URL) async throws -> [String: Any] {
        let logger = Logger(label: "PythonPlanner")
        
        // Convert graph to JSON for Python consumption
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let tempGraphFile: URL
        do {
            let graphData = try encoder.encode(graph)
            logger.debug("Successfully encoded graph to JSON, size: \(graphData.count) bytes")
            
            // Write graph to temporary file
            tempGraphFile = URL(fileURLWithPath: "/tmp/agently_graph.json")
            try graphData.write(to: tempGraphFile)
            logger.debug("Successfully wrote graph to: \(tempGraphFile.path)")
            
            // Verify file exists
            if FileManager.default.fileExists(atPath: tempGraphFile.path) {
                logger.debug("Graph file exists at: \(tempGraphFile.path)")
            } else {
                logger.error("Graph file was not created at: \(tempGraphFile.path)")
                throw AgentlyError.planningFailed("Failed to create graph file")
            }
        } catch {
            logger.error("Failed to encode or write graph: \(error)")
            throw AgentlyError.planningFailed("Graph encoding failed: \(error)")
        }
        
        // Write task to temporary file to avoid shell escaping issues
        let tempTaskFile = URL(fileURLWithPath: "/tmp/agently_task.txt")
        try task.write(to: tempTaskFile, atomically: true, encoding: .utf8)
        logger.debug("Wrote task to: \(tempTaskFile.path)")
        
        // Call Python planner script using virtual environment
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        let llmLoggingFlag = enableLlmLogging ? " --enable-llm-logging --log-dir '\(runDir.path)'" : ""
        process.arguments = ["-c", "cd \(FileManager.default.currentDirectoryPath) && source venv/bin/activate && python3 -m planner.main --task-file '\(tempTaskFile.path)' --graph '\(tempGraphFile.path)'\(llmLoggingFlag)"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        // Log stderr for debugging
        if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
            logger.debug("Python planner stderr: \(errorOutput)")
        }
        
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw AgentlyError.planningFailed("No output from planner")
        }
        
        // Clean up
        try? FileManager.default.removeItem(at: tempGraphFile)
        
        // Debug the actual output
        logger.debug("Python planner stdout: \(output)")
        
        // Check for process exit code
        if process.terminationStatus != 0 {
            throw AgentlyError.planningFailed("Python planner exited with code \(process.terminationStatus)")
        }
        
        guard let jsonData = output.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw AgentlyError.planningFailed("Invalid JSON response from planner. Output was: \(output)")
        }
        
        return result
    }
    
    private func callPythonPlannerForRecovery(
        task: String,
        graph: UIGraph,
        failedAction: [String: Any],
        error: String,
        completedActions: [SkillResult],
        runDir: URL
    ) async throws -> [String: Any] {
        // Convert graph to JSON for Python consumption
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let graphData = try encoder.encode(graph)
        
        // Write graph to temporary file
        let tempGraphFile = URL(fileURLWithPath: "/tmp/agently_recovery_graph.json")
        try graphData.write(to: tempGraphFile)
        
        // Write action data to temporary files to avoid shell escaping issues
        let tempFailedActionFile = URL(fileURLWithPath: "/tmp/agently_failed_action.json")
        let tempCompletedActionsFile = URL(fileURLWithPath: "/tmp/agently_completed_actions.json")
        
        let failedActionData = try JSONSerialization.data(withJSONObject: failedAction, options: .prettyPrinted)
        try failedActionData.write(to: tempFailedActionFile)
        
        let completedActionsData = try JSONSerialization.data(withJSONObject: completedActions.map { result in
            [
                "type": result.action.type.rawValue,
                "description": result.action.description,
                "success": result.success
            ]
        }, options: .prettyPrinted)
        try completedActionsData.write(to: tempCompletedActionsFile)
        
        // Call Python recovery planner
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        let llmLoggingFlag = enableLlmLogging ? " --enable-llm-logging --log-dir '\(runDir.path)'" : ""
        
        // Properly escape arguments by using separate arguments instead of a single shell command
        let escapedTask = task.replacingOccurrences(of: "'", with: "'\"'\"'")
        let escapedError = error.replacingOccurrences(of: "'", with: "'\"'\"'")
        
        process.arguments = ["-c", "cd '\(FileManager.default.currentDirectoryPath)' && source venv/bin/activate && python3 -m planner.main --task '\(escapedTask)' --graph '\(tempGraphFile.path)' --recovery --failed-action-file '\(tempFailedActionFile.path)' --error-message '\(escapedError)' --completed-actions-file '\(tempCompletedActionsFile.path)'\(llmLoggingFlag)"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        // Log stderr for debugging
        if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
            let logger = Logger(label: "PythonRecoveryPlanner")
            logger.debug("Python recovery planner stderr: \(errorOutput)")
        }
        
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw AgentlyError.planningFailed("No output from recovery planner")
        }
        
        // Clean up
        try? FileManager.default.removeItem(at: tempGraphFile)
        
        // Parse result
        guard let data = output.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentlyError.planningFailed("Invalid JSON response from recovery planner")
        }
        
        return result
    }
    
    private func parseAction(from data: [String: Any]) -> SkillAction {
        let type = ActionType(rawValue: data["type"] as? String ?? "") ?? .click
        let targetElementId = data["target_element_id"] as? String
        
        // Convert all parameter values to strings to handle mixed types from JSON
        var parameters: [String: String] = [:]
        if let rawParameters = data["parameters"] as? [String: Any] {
            for (key, value) in rawParameters {
                parameters[key] = String(describing: value)
            }
        }
        
        let description = data["description"] as? String ?? "Unknown action"
        
        return SkillAction(
            type: type,
            targetElementId: targetElementId,
            parameters: parameters,
            description: description
        )
    }
    
    private func parseActionWithElementResolution(from data: [String: Any], in graph: UIGraph) -> SkillAction {
        let type = ActionType(rawValue: data["type"] as? String ?? "") ?? .click
        let rawTargetElementId = data["target_element_id"] as? String
        
        // Resolve element ID if it looks like a semantic reference
        let targetElementId = resolveElementId(rawTargetElementId, in: graph)
        
        // Convert all parameter values to strings to handle mixed types from JSON
        var parameters: [String: String] = [:]
        if let rawParameters = data["parameters"] as? [String: Any] {
            for (key, value) in rawParameters {
                parameters[key] = String(describing: value)
            }
        }
        
        let description = data["description"] as? String ?? "Unknown action"
        
        return SkillAction(
            type: type,
            targetElementId: targetElementId,
            parameters: parameters,
            description: description
        )
    }
    
    private func resolveElementId(_ rawId: String?, in graph: UIGraph) -> String? {
        guard let rawId = rawId else { return nil }
        
        // If it's already a proper element ID (starts with "elem_"), use it as is
        if rawId.hasPrefix("elem_") {
            return rawId
        }
        
        // Try to parse semantic references like "AXButton label:'Save'" or "AXTextField title:'Username'"
        if let colonIndex = rawId.firstIndex(of: ":"),
           let startQuote = rawId[rawId.index(after: colonIndex)...].firstIndex(of: "'"),
           let endQuote = rawId[rawId.index(after: startQuote)...].firstIndex(of: "'") {
            
            let roleAndProperty = String(rawId[..<colonIndex])
            let searchText = String(rawId[rawId.index(after: startQuote)..<endQuote])
            
            // Extract role (everything before the first space)
            let roleParts = roleAndProperty.split(separator: " ", maxSplits: 1)
            guard let role = roleParts.first else { return rawId }
            
            // Extract property (label, title, value) if specified
            let property = roleParts.count > 1 ? String(roleParts[1]) : "any"
            
            // Find elements with matching role
            let roleElements = graph.elements(withRole: String(role))
            for element in roleElements {
                // Check the specified property or any property if not specified
                let matches = property == "any" || 
                    (property == "label" && element.label == searchText) ||
                    (property == "title" && element.title == searchText) ||
                    (property == "value" && element.value == searchText)
                
                if matches || (property == "any" && 
                    (element.label == searchText || element.title == searchText || element.value == searchText)) {
                    return element.id
                }
            }
        }
        
        // Try legacy format "AXButton 'text'" for backward compatibility
        else if let spaceIndex = rawId.firstIndex(of: " "),
                let startQuote = rawId[rawId.index(after: spaceIndex)...].firstIndex(of: "'"),
                let endQuote = rawId[rawId.index(after: startQuote)...].firstIndex(of: "'") {
            
            let role = String(rawId[..<spaceIndex])
            let searchText = String(rawId[rawId.index(after: startQuote)..<endQuote])
            
            let roleElements = graph.elements(withRole: role)
            for element in roleElements {
                if element.label == searchText || element.title == searchText || element.value == searchText {
                    return element.id
                }
            }
        }
        
        // Fallback: try to find any element containing the text
        let matchingElements = graph.elements(containing: rawId)
        if let firstMatch = matchingElements.first {
            return firstMatch.id
        }
        
        // If all else fails, return the raw ID and let the execution layer handle the error
        return rawId
    }
    
    private func verifyStep(
        stepDescription: String,
        actionType: String,
        actionDescription: String,
        runDir: URL,
        userTask: String,
        completedActions: [String]
    ) async throws -> VerificationResult {
        let logger = Logger(label: "StepVerification")
        logger.info("Verifying step: \(stepDescription)")
        
        // Write arguments to temporary files to avoid shell escaping issues
        let tempStepDescFile = URL(fileURLWithPath: "/tmp/agently_step_desc.txt")
        let tempActionTypeFile = URL(fileURLWithPath: "/tmp/agently_action_type.txt")
        let tempActionDescFile = URL(fileURLWithPath: "/tmp/agently_action_desc.txt")
        let tempUserTaskFile = URL(fileURLWithPath: "/tmp/agently_user_task.txt")
        let tempCompletedActionsFile = URL(fileURLWithPath: "/tmp/agently_completed_actions.txt")
        
        try stepDescription.write(to: tempStepDescFile, atomically: true, encoding: .utf8)
        try actionType.write(to: tempActionTypeFile, atomically: true, encoding: .utf8)
        try actionDescription.write(to: tempActionDescFile, atomically: true, encoding: .utf8)
        try userTask.write(to: tempUserTaskFile, atomically: true, encoding: .utf8)
        
        // Write completed actions as JSON array
        let completedActionsData = try JSONSerialization.data(withJSONObject: completedActions)
        try completedActionsData.write(to: tempCompletedActionsFile)
        
        logger.debug("Wrote verification arguments to temp files")
        
        // Call Python verification script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        
        // Use virtual environment
        let verifyScript = URL(fileURLWithPath: "planner/verify_step.py")
        
        let arguments = [
            "-c",
            "source venv/bin/activate && python \(verifyScript.path) --step-description-file '\(tempStepDescFile.path)' --action-type-file '\(tempActionTypeFile.path)' --action-description-file '\(tempActionDescFile.path)' --user-task-file '\(tempUserTaskFile.path)' --completed-actions-file '\(tempCompletedActionsFile.path)' --run-dir '\(runDir.path)'"
        ]
        
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw AgentlyError.executionFailed("Failed to read verification output")
        }
        
        if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
            logger.debug("Verification stderr: \(errorOutput)")
        }
        
        // Parse JSON response regardless of exit code (failed verification is expected)
        guard let jsonData = output.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            logger.error("Failed to parse JSON from output: \(output)")
            throw AgentlyError.executionFailed("Invalid JSON response from verifier")
        }
        
        // Log verification process status for debugging
        if process.terminationStatus != 0 {
            logger.debug("Verification script exited with code \(process.terminationStatus) (expected for failed verification)")
        }
        

        
        let success = result["success"] as? Bool ?? false
        let confidence = result["confidence"] as? Double ?? 0.0
        let reasoning = result["reasoning"] as? String ?? "No reasoning provided"
        let shouldRetry = result["should_retry"] as? Bool ?? false
        let retryReason = result["retry_reason"] as? String ?? "Unknown reason"
        let screenshotPath = result["screenshot_path"] as? String
        let uiGraphPath = result["ui_graph_path"] as? String
        let planUpdate = result["plan_update"] as? [String: Any]
        
        logger.info("Verification result: success=\(success), confidence=\(confidence)")
        
        return VerificationResult(
            success: success,
            confidence: confidence,
            reasoning: reasoning,
            shouldRetry: shouldRetry,
            retryReason: retryReason,
            screenshotPath: screenshotPath,
            uiGraphPath: uiGraphPath,
            planUpdate: planUpdate
        )
    }
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case json
    case text
}

enum AgentlyError: Error, LocalizedError {
    case planningFailed(String)
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .planningFailed(let message):
            return "Planning failed: \(message)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        }
    }
}
