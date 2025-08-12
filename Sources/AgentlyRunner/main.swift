import ArgumentParser
import ApplicationServices
import Foundation
import Logging
import UIGraph
import Skills

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
        
        // 3. Execute actions
        let skillExecutor = SkillExecutor()
        var currentGraph = initialGraph
        var executedActions: [SkillResult] = []
        
        for (index, actionData) in actions.enumerated() {
            logger.info("Executing action \(index + 1)/\(actions.count)")
            
            do {
                let action = parseAction(from: actionData)
                let result = skillExecutor.execute(action, in: currentGraph)
                executedActions.append(result)
                
                if !result.success {
                    logger.error("Action failed: \(result.errorMessage ?? "unknown error")")
                    
                    // Try to recover
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
                        
                        // If recovery failed, stop execution
                        if !recoverySuccessful {
                            logger.error("Recovery failed, stopping execution")
                            break
                        }
                        
                        logger.info("Recovery completed successfully")
                    } else {
                        logger.error("No recovery plan available, stopping execution")
                        break
                    }
                }
                
                // Update graph after successful action
                if result.success {
                    // Small delay to let UI settle
                    try await Task.sleep(for: .milliseconds(500))
                    currentGraph = try graphBuilder.buildGraph()
                    
                    // Save graph after each action for inspection
                    try runLogger.saveGraphToRunDirectory(currentGraph, filename: "\(String(format: "%02d", index + 1))_after_\(action.type.rawValue)", runDir: runDir)
                }
                
            } catch {
                logger.error("Failed to execute action: \(error)")
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
        // Convert graph to JSON for Python consumption
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let graphData = try encoder.encode(graph)
        
        // Write graph to temporary file
        let tempGraphFile = URL(fileURLWithPath: "/tmp/agently_graph.json")
        try graphData.write(to: tempGraphFile)
        
        // Call Python planner script using virtual environment
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        let llmLoggingFlag = enableLlmLogging ? " --enable-llm-logging --log-dir '\(runDir.path)'" : ""
        process.arguments = ["-c", "cd \(FileManager.default.currentDirectoryPath) && source venv/bin/activate && python3 -m planner.main --task '\(task)' --graph '\(tempGraphFile.path)'\(llmLoggingFlag)"]
        
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
            let logger = Logger(label: "PythonPlanner")
            logger.debug("Python planner stderr: \(errorOutput)")
        }
        
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw AgentlyError.planningFailed("No output from planner")
        }
        
        // Clean up
        try? FileManager.default.removeItem(at: tempGraphFile)
        
        // Debug the actual output
        let logger = Logger(label: "PythonPlanner")
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
