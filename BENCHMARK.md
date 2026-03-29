#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 8.570 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 77.600 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 763.380 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 7.681 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 80.946 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 3.620 us/op | 6.31 KiB/op | 3/op |
| Create 1000 Entities | 10 | 44.700 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 379.100 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.787 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 38.923 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 1.780 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 7.090 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 61.060 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 608.780 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.497 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 80.350 us/op | 119 B/op | 10/op |
| 1000 Entities, 3 Stages | 10 | 68.000 us/op | 119 B/op | 10/op |
| 10000 Entities, 3 Stages | 10 | 121.160 us/op | 119 B/op | 10/op |
| 100000 Entities, 3 Stages | 10 | 574.880 us/op | 119 B/op | 10/op |
| 1000000 Entities, 3 Stages | 10 | 5.599 ms/op | 119 B/op | 10/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 3.130 us/op | 12.31 KiB/op | 7/op |
| Run CRUD System on 1000 Entities | 10 | 20.610 us/op | 20.71 KiB/op | 8/op |
| Run CRUD System on 10000 Entities | 10 | 146.260 us/op | 90.00 KiB/op | 8/op |
| Run CRUD System on 100000 Entities | 10 | 1.898 ms/op | 1.23 MiB/op | 9/op |
| Run CRUD System on 1000000 Entities | 10 | 18.504 ms/op | 9.91 MiB/op | 10/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.270 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.720 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 104.370 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.063 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 10.854 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 1.517 ms/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 2.571 ms/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 3.777 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 10.656 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 107.148 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 56.640 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 168.790 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.407 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 14.306 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 143.445 ms/op | 0 B/op | 0/op |

