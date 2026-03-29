#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 8.630 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 74.600 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 771.460 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 7.530 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 81.353 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 3.470 us/op | 6.31 KiB/op | 3/op |
| Create 1000 Entities | 10 | 43.570 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 379.180 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.781 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 38.695 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 1.860 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 7.380 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 62.260 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 610.040 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.557 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 80.770 us/op | 119 B/op | 10/op |
| 1000 Entities, 3 Stages | 10 | 81.560 us/op | 119 B/op | 10/op |
| 10000 Entities, 3 Stages | 10 | 110.390 us/op | 119 B/op | 10/op |
| 100000 Entities, 3 Stages | 10 | 609.120 us/op | 119 B/op | 10/op |
| 1000000 Entities, 3 Stages | 10 | 5.739 ms/op | 119 B/op | 10/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 3.010 us/op | 12.31 KiB/op | 7/op |
| Run CRUD System on 1000 Entities | 10 | 20.430 us/op | 20.71 KiB/op | 8/op |
| Run CRUD System on 10000 Entities | 10 | 139.510 us/op | 90.00 KiB/op | 8/op |
| Run CRUD System on 100000 Entities | 10 | 1.844 ms/op | 1.23 MiB/op | 9/op |
| Run CRUD System on 1000000 Entities | 10 | 18.202 ms/op | 9.91 MiB/op | 10/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.270 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.580 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 107.230 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.107 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 10.929 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 1.376 ms/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 2.394 ms/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 4.170 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 10.716 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 106.732 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 58.660 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 173.300 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.474 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 14.890 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 148.917 ms/op | 0 B/op | 0/op |

