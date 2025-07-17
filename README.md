# ZProxy

ZProxy is an HTTP/HTTPS reverse proxy engineered for **extreme performance**
and **predictable behavior**. It uses a **shared-nothing event loop architecture**
with **zero runtime memory allocation** to deliver consistent speed and reliability.

### **⚡ Key Features**

- **High Performance**: 100K+ RPS per core with sub-millisecond latency
- **Zero Allocation**: No memory allocation after startup - completely predictable memory usage
- **Shared-Nothing**: Independent event loops per CPU core eliminate contention
- **Linear Scaling**: Process-per-core design with `SO_REUSEPORT` for perfect scaling
- **Memory Safe**: Compile-time safety without garbage collection overhead

### **Shared-Nothing Event Loops**

```zig
// Independent process per CPU core
for (0..cpu_count) |core_id| {
    const worker = try ZProxy.init(config);
    worker.bind_cpu(core_id);           // CPU affinity
    worker.listen_with_reuseport(port); // Kernel load balancing
    // Each worker: isolated memory, no shared state, no locks
}


```
