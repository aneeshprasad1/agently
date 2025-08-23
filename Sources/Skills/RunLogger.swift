import Foundation
import Logging
import UIGraph

/// Handles logging of execution runs, UI graphs, and results for Agently.
/// Provides organized directory structure and detailed logging capabilities.
public class RunLogger {
    private let logger = Logger(label: "RunLogger")
    
    public init() {}
    
    /// Creates a new run directory with organized structure.
    /// - Parameter task: The task description for this run
    /// - Returns: URL of the created run directory
    /// - Throws: Error if directory creation fails
    public func createRunDirectory(task: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        
        // Sanitize task for filename
        let sanitizedTask = task
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .prefix(50) // Limit length
        
        let runName = "\(timestamp)_\(sanitizedTask)"
        let runsDir = URL(fileURLWithPath: "logs/runs")
        let runDir = runsDir.appendingPathComponent(runName)
        
        // Create directory structure
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runDir.appendingPathComponent("ui_graphs"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runDir.appendingPathComponent("llm_conversations"), withIntermediateDirectories: true)
        
        // Create run metadata
        let metadata: [String: Any] = [
            "task": task,
            "start_time": ISO8601DateFormatter().string(from: Date()),
            "run_id": runName
        ]
        
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
        try metadataData.write(to: runDir.appendingPathComponent("run_metadata.json"))
        
        return runDir
    }
    
    /// Saves a UI graph to the run directory with both full JSON and summary.
    /// - Parameters:
    ///   - graph: The UI graph to save
    ///   - filename: Base filename (without extension)
    ///   - runDir: The run directory URL
    /// - Throws: Error if saving fails
    public func saveGraphToRunDirectory(_ graph: UIGraph, filename: String, runDir: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(graph)
        
        // Save to ui_graphs subdirectory
        let graphsDir = runDir.appendingPathComponent("ui_graphs")
        let graphFile = graphsDir.appendingPathComponent("\(filename).json")
        try data.write(to: graphFile)
        
        // Also save a summary
        let summary = createGraphSummary(graph)
        let summaryFile = graphsDir.appendingPathComponent("\(filename)_summary.txt")
        try summary.write(to: summaryFile, atomically: true, encoding: .utf8)
        
        print("📊 Saved graph (\(graph.elements.count) elements) to: \(graphFile.path)")
    }
    
    /// Saves execution results and creates execution log.
    /// - Parameters:
    ///   - task: The task description
    ///   - executedActions: Array of executed skill results
    ///   - runDir: The run directory URL
    /// - Throws: Error if saving fails
    public func saveExecutionResults(task: String, executedActions: [SkillResult], runDir: URL) throws {
        let successCount = executedActions.filter { $0.success }.count
        let totalTime = executedActions.reduce(0) { $0 + $1.executionTime }
        
        let results: [String: Any] = [
            "task": task,
            "completion_time": ISO8601DateFormatter().string(from: Date()),
            "total_actions": executedActions.count,
            "successful_actions": successCount,
            "success_rate": executedActions.isEmpty ? 0.0 : Double(successCount) / Double(executedActions.count),
            "total_execution_time": totalTime,
            "actions": executedActions.map { result in
                [
                    "type": result.action.actionType.rawValue,
                    "description": result.action.description,
                    "success": result.success,
                    "execution_time": result.executionTime,
                    "timestamp": ISO8601DateFormatter().string(from: result.timestamp),
                    "error": result.errorMessage as Any
                ]
            }
        ]
        
        let data = try JSONSerialization.data(withJSONObject: results, options: .prettyPrinted)
        try data.write(to: runDir.appendingPathComponent("results_summary.json"))
        
        // Also create a simple execution log
        var logText = "# Execution Log\\n\\n"
        logText += "**Task:** \(task)\\n"
        logText += "**Total Actions:** \(executedActions.count)\\n"
        logText += "**Successful:** \(successCount)\\n"
        logText += "**Success Rate:** \(String(format: "%.1f", (Double(successCount) / Double(executedActions.count)) * 100))%\\n"
        logText += "**Total Time:** \(String(format: "%.3f", totalTime))s\\n\\n"
        
        logText += "## Action Details\\n\\n"
        for (index, result) in executedActions.enumerated() {
            let status = result.success ? "✅" : "❌"
            logText += "\(index + 1). \(status) **\(result.action.actionType.rawValue)** - \(result.action.description)\\n"
            if let error = result.errorMessage {
                logText += "   Error: \(error)\\n"
            }
            logText += "   Time: \(String(format: "%.3f", result.executionTime))s\\n\\n"
        }
        
        try logText.write(to: runDir.appendingPathComponent("execution_log.md"), atomically: true, encoding: .utf8)
    }
    
    /// Saves a UI graph to a standalone directory (for --graph-only mode).
    /// - Parameters:
    ///   - graph: The UI graph to save
    ///   - filename: Base filename (without extension)
    ///   - directory: The directory to save to
    /// - Throws: Error if saving fails
    public func saveGraphToFile(_ graph: UIGraph, filename: String, directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(graph)
        
        // Save full graph
        let fullGraphFile = directory.appendingPathComponent("\(filename).json")
        try data.write(to: fullGraphFile)
        
        // Also save a summary with application breakdown
        let summary = createGraphSummary(graph)
        let summaryFile = directory.appendingPathComponent("\(filename)_summary.txt")
        try summary.write(to: summaryFile, atomically: true, encoding: .utf8)
        
        print("📊 Saved graph (\(graph.elements.count) elements) to: \(fullGraphFile.path)")
        print("📋 Saved summary to: \(summaryFile.path)")
    }
    
    /// Creates a human-readable summary of a UI graph.
    /// - Parameter graph: The UI graph to summarize
    /// - Returns: A formatted string summary
    public func createGraphSummary(_ graph: UIGraph) -> String {
        var summary = """
        Accessibility Graph Summary
        ===========================
        Timestamp: \(graph.timestamp)
        Active Application: \(graph.activeApplication ?? "Unknown")
        Total Elements: \(graph.elements.count)
        
        Applications and Element Counts:
        """
        
        // Group elements by application
        let appCounts = Dictionary(grouping: graph.elements.values, by: { $0.applicationName })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        
        for (app, count) in appCounts {
            summary += "\n- \(app): \(count) elements"
        }
        
        summary += "\n\nTop Element Roles:"
        let roleCounts = Dictionary(grouping: graph.elements.values, by: { $0.role })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        
        for (role, count) in Array(roleCounts.prefix(10)) {
            summary += "\n- \(role): \(count)"
        }
        
        return summary
    }
    
    /// Prints a summary of the UI graph to the logger.
    /// - Parameter graph: The UI graph to summarize
    public func printGraphSummary(_ graph: UIGraph) {
        logger.info("UI Graph Summary:")
        logger.info("- Timestamp: \(graph.timestamp)")
        logger.info("- Active Application: \(graph.activeApplication ?? "None")")
        logger.info("- Total Elements: \(graph.elements.count)")
        logger.info("- Root Elements: \(graph.rootElements.count)")
        
        // Count by role
        let roleCounts = Dictionary(grouping: graph.elements.values) { $0.role }
            .mapValues { $0.count }
        
        logger.info("- Element Types:")
        for (role, count) in roleCounts.sorted(by: { $0.value > $1.value }) {
            logger.info("  - \(role): \(count)")
        }
        
        // Show some example elements
        let interactiveElements = graph.elements.values.filter { element in
            ["AXButton", "AXTextField", "AXMenuButton", "AXCheckBox"].contains(element.role)
        }
        
        if !interactiveElements.isEmpty {
            logger.info("- Sample Interactive Elements:")
            for element in Array(interactiveElements.prefix(5)) {
                let label = element.label ?? element.title ?? "unlabeled"
                logger.info("  - \(element.role): '\(label)' [\(element.id)]")
            }
        }
    }
}
