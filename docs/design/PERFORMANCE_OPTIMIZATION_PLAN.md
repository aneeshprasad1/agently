# Agently Performance Optimization Plan

## Executive Summary

Analysis of the Agently system reveals significant performance optimization opportunities that could improve execution speed by 3-10x. The primary bottleneck is UI graph building, which accounts for 68% of execution time. This document outlines a comprehensive optimization strategy.

## Current Performance Baseline

### Measured Performance (Real Execution)
| Task | Human Baseline | Current Time | Slowdown | Target Time | Target Slowdown |
|------|----------------|--------------|----------|-------------|-----------------|
| Calculator Open | 3.5s | 22s | 6.3x | 7-10s | 2-3x |
| Safari Navigate | 25s | 38s | 1.5x | 30-35s | 1.2-1.4x |
| Messages Compose | 45s | 104s | 2.3x | 60-75s | 1.3-1.7x |

### Time Breakdown Analysis
Based on detailed profiling of Calculator Open task (44s total):

| Component | Time | % Total | Optimization Potential |
|-----------|------|---------|----------------------|
| **UI Graph Building** | 30s (5×6s) | 68% | **HIGH** - 50-80% reduction |
| **LLM Planning** | 6s | 14% | **MEDIUM** - 20-40% reduction |
| **Action Execution** | 3s | 7% | **LOW** - 10-20% reduction |
| **Swift Build** | 0.5s | 1% | **LOW** - Already optimized |
| **Other Overhead** | 4s | 10% | **MEDIUM** - 30-50% reduction |

## Optimization Strategy

### Phase 1: High-Impact UI Graph Optimizations (Target: 50-70% speedup)

#### 1.1 Smart Graph Rebuilding
**Problem**: Currently rebuilds entire UI graph after every action (5×6s = 30s)
**Solution**: Conditional rebuilding based on action type and context

```swift
enum GraphRebuildStrategy {
    case always           // Current behavior
    case onAppChange      // Only when switching applications
    case onStructureChange // Only for actions that modify UI structure
    case cached           // Use cached graph when possible
    case selective        // Rebuild only relevant portions
}
```

**Implementation:**
- **Immediate**: Skip rebuilds for `wait`, `key_press` actions → Save 12s
- **Short-term**: Cache graphs per application → Save 18s  
- **Medium-term**: Incremental graph updates → Save 24s

**Expected Impact**: 40-80% reduction in graph building time

#### 1.2 Scope-Limited Graph Building
**Problem**: Scanning 748 elements across entire system
**Solution**: Focus on active application and relevant windows only

```swift
struct GraphBuildingConfig {
    let maxElements: Int = 200        // Down from 5000
    let focusActiveApp: Bool = true   // Only scan active application
    let includeSystemUI: Bool = false // Skip system elements when possible
    let maxDepth: Int = 8            // Down from 10
}
```

**Expected Impact**: 30-60% reduction in individual graph build time

#### 1.3 Parallel Graph Processing
**Problem**: Sequential processing of graph building and LLM planning
**Solution**: Pipeline operations where possible

```swift
// While LLM is planning, pre-build next graph in background
async func executeWithPipelining() {
    let graphTask = buildNextGraph()
    let planningTask = callLLMPlanner()
    
    let (graph, plan) = await (graphTask, planningTask)
    // Execute with both ready
}
```

**Expected Impact**: 20-40% reduction in total execution time

### Phase 2: LLM Planning Optimizations (Target: 20-40% speedup)

#### 2.1 Model Selection Strategy
**Current**: GPT-4o-mini for all tasks
**Optimization**: Dynamic model selection based on task complexity

```python
class ModelSelector:
    def select_model(self, task_complexity: str, ui_elements: int) -> str:
        if task_complexity == "low" and ui_elements < 50:
            return "gpt-3.5-turbo"  # 2x faster, cheaper
        elif task_complexity == "medium":
            return "gpt-4o-mini"    # Current default
        else:
            return "gpt-4o"         # For complex tasks
```

**Expected Impact**: 30-50% reduction in planning time for simple tasks

#### 2.2 Context Optimization
**Problem**: Sending full UI graph (748 elements) to LLM
**Solution**: Intelligent context filtering

```python
def optimize_context(ui_graph: dict, task: str) -> dict:
    # Extract only relevant UI elements for the task
    relevant_elements = filter_by_relevance(ui_graph, task)
    # Limit to top 50 most relevant elements
    return {
        "elements": relevant_elements[:50],
        "summary": generate_summary(ui_graph),
        "active_app": ui_graph["activeApplication"]
    }
```

**Expected Impact**: 20-40% reduction in planning time, lower API costs

#### 2.3 Plan Caching
**Problem**: Re-planning similar tasks from scratch
**Solution**: Cache and reuse plans for similar contexts

```python
class PlanCache:
    def get_cached_plan(self, task_hash: str, context_hash: str) -> Optional[Plan]:
        # Return cached plan if context is similar enough
        pass
    
    def cache_plan(self, task: str, context: dict, plan: Plan):
        # Store plan with context fingerprint
        pass
```

**Expected Impact**: 80-95% reduction for repeated similar tasks

### Phase 3: Action Execution Optimizations (Target: 10-30% speedup)

#### 3.1 Batch Action Execution
**Problem**: Sequential execution with graph rebuilds between each action
**Solution**: Group compatible actions for batch execution

```swift
func executeBatch(_ actions: [SkillAction]) -> [SkillResult] {
    let batchableActions = groupBatchableActions(actions)
    var results: [SkillResult] = []
    
    for batch in batchableActions {
        // Execute all actions in batch without rebuilding graph
        let batchResults = batch.map { execute($0, skipGraphRebuild: true) }
        results.append(contentsOf: batchResults)
        
        // Rebuild graph only once per batch
        rebuildGraph()
    }
    
    return results
}
```

**Expected Impact**: 20-40% reduction in action execution overhead

#### 3.2 Optimized Element Targeting
**Problem**: Linear search through UI elements for targeting
**Solution**: Spatial indexing and caching

```swift
class UIElementIndex {
    private var spatialIndex: QuadTree<UIElement>
    private var roleIndex: [String: [UIElement]]
    private var textIndex: [String: [UIElement]]
    
    func findOptimalElement(for action: SkillAction) -> UIElement? {
        // Use spatial/semantic indexing for O(log n) lookup
        // instead of O(n) linear search
    }
}
```

**Expected Impact**: 10-30% reduction in element targeting time

### Phase 4: System-Level Optimizations (Target: 10-20% speedup)

#### 4.1 Memory Management
**Problem**: Potential memory pressure from large UI graphs
**Solution**: Efficient memory usage and garbage collection

```swift
struct OptimizedUIGraph {
    // Use value types and copy-on-write for efficiency
    private var elements: ContiguousArray<UIElement>
    private var elementIndex: [String: Int]
    
    func element(withId id: String) -> UIElement? {
        // O(1) lookup instead of O(n) search
    }
}
```

#### 4.2 Logging Optimization
**Problem**: Extensive logging affecting performance
**Solution**: Async logging and configurable verbosity

```swift
struct OptimizedLogger {
    let isDebugEnabled: Bool
    let asyncQueue: DispatchQueue
    
    func debug(_ message: String) {
        guard isDebugEnabled else { return }
        asyncQueue.async { self.write(message) }
    }
}
```

## Implementation Roadmap

### Sprint 1 (Quick Wins - 1-2 weeks)
- [ ] Skip graph rebuilds for `wait` and simple `key_press` actions
- [ ] Reduce max elements from 5000 to 1000 for initial testing
- [ ] Add performance timing to all major operations
- [ ] Implement basic model selection (gpt-3.5-turbo for simple tasks)

**Expected Impact**: 30-50% speedup

### Sprint 2 (Medium Impact - 2-3 weeks)  
- [ ] Implement application-focused graph building
- [ ] Add LLM context optimization (relevant elements only)
- [ ] Create graph caching mechanism
- [ ] Optimize element targeting with indexing

**Expected Impact**: Additional 40-60% speedup

### Sprint 3 (Advanced Optimizations - 3-4 weeks)
- [ ] Implement parallel processing pipeline
- [ ] Add plan caching system
- [ ] Create batch action execution
- [ ] Implement incremental graph updates

**Expected Impact**: Additional 20-40% speedup

### Sprint 4 (Polish & Monitoring - 1-2 weeks)
- [ ] Add comprehensive performance monitoring
- [ ] Create optimization configuration system
- [ ] Implement A/B testing framework for optimizations
- [ ] Documentation and best practices guide

## Success Metrics

### Primary Metrics
- **Execution Time**: Target 50-70% reduction in total task time
- **Human Parity**: Achieve 1.5-2.5x human baseline (down from 1.5-6.3x)
- **Reliability**: Maintain >95% success rate while optimizing

### Secondary Metrics  
- **Resource Usage**: Reduce memory usage by 30-50%
- **API Costs**: Reduce LLM API costs by 40-60% through context optimization
- **Developer Experience**: Sub-second feedback for common development tasks

## Risk Mitigation

### Performance Regression Prevention
- Comprehensive benchmarking suite with performance regression detection
- A/B testing framework to validate optimizations
- Rollback mechanisms for each optimization phase

### Reliability Maintenance
- Extensive testing on all supported macOS versions
- Graceful degradation when optimizations fail
- Performance vs accuracy trade-off monitoring

## Monitoring & Observability

### Performance Dashboards
```yaml
metrics:
  execution_time:
    - total_task_time
    - graph_build_time  
    - llm_planning_time
    - action_execution_time
  
  success_rates:
    - overall_success_rate
    - success_rate_by_complexity
    - optimization_impact_on_success
  
  resource_usage:
    - memory_usage_peak
    - cpu_utilization
    - api_call_frequency
```

### Alerting
- Performance regression alerts (>20% slowdown)
- Success rate degradation alerts (<90% success)
- Resource usage anomaly detection

## Future Research Areas

### Advanced Optimizations (6+ months)
- **Machine Learning**: Learn optimal graph scanning patterns
- **Predictive Caching**: Predict which UI elements will be needed
- **Distributed Processing**: Offload graph building to separate processes
- **Native Optimization**: Replace accessibility API calls with faster alternatives

### Experimental Features
- **Visual Recognition**: Use computer vision to reduce dependency on accessibility APIs
- **Pattern Recognition**: Learn from user behavior to optimize common workflows
- **Hardware Acceleration**: GPU-based graph processing for complex UIs

## Conclusion

The proposed optimizations could realistically achieve:
- **3-5x speedup** for simple tasks (Calculator: 22s → 5-7s)
- **2-3x speedup** for complex tasks (Messages: 104s → 35-50s)
- **50-70% reduction** in resource usage
- **Maintained reliability** with comprehensive testing

Priority should be given to Phase 1 optimizations (UI Graph) as they provide the highest impact with relatively low implementation risk.
