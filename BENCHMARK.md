#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 7.400 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 74.500 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 672.150 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 7.626 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 87.145 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 3.300 us/op | 6.31 KiB/op | 3/op |
| Create 1000 Entities | 10 | 57.400 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 400.400 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.440 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 35.881 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 1.300 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 7.150 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 61.650 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 607.850 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.602 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 45.400 us/op | 7 B/op | 7/op |
| 1000 Entities, 3 Stages | 10 | 42.050 us/op | 7 B/op | 7/op |
| 10000 Entities, 3 Stages | 10 | 81.100 us/op | 7 B/op | 7/op |
| 100000 Entities, 3 Stages | 10 | 497.350 us/op | 7 B/op | 7/op |
| 1000000 Entities, 3 Stages | 10 | 5.683 ms/op | 7 B/op | 7/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 4.600 us/op | 13.27 KiB/op | 17/op |
| Run CRUD System on 1000 Entities | 10 | 20.100 us/op | 24.80 KiB/op | 17/op |
| Run CRUD System on 10000 Entities | 10 | 152.450 us/op | 125.50 KiB/op | 18/op |
| Run CRUD System on 100000 Entities | 10 | 1.854 ms/op | 1.57 MiB/op | 19/op |
| Run CRUD System on 1000000 Entities | 10 | 30.101 ms/op | 13.32 MiB/op | 19/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.300 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.550 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 105.200 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.122 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 11.147 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 263.950 us/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 2.264 ms/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 4.396 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 10.560 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 103.538 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 46.900 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 163.600 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.393 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 14.237 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 143.162 ms/op | 0 B/op | 0/op |

#### Resource Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 1 Resources | 10 | 250.000 ns/op | 0 B/op | 0/op |
| Serialize 2 Resources | 10 | 500.000 ns/op | 0 B/op | 0/op |
| Serialize 4 Resources | 10 | 500.000 ns/op | 0 B/op | 0/op |
| Serialize 6 Resources | 10 | 1.400 us/op | 0 B/op | 0/op |
| Serialize 8 Resources | 10 | 750.000 ns/op | 0 B/op | 0/op |
| Serialize 10 Resources | 10 | 950.000 ns/op | 0 B/op | 0/op |

#### Resource Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 1 Resources | 10 | 150.000 ns/op | 0 B/op | 0/op |
| Deserialize 2 Resources | 10 | 300.000 ns/op | 0 B/op | 0/op |
| Deserialize 4 Resources | 10 | 600.000 ns/op | 0 B/op | 0/op |
| Deserialize 6 Resources | 10 | 800.000 ns/op | 0 B/op | 0/op |
| Deserialize 8 Resources | 10 | 1.100 us/op | 0 B/op | 0/op |
| Deserialize 10 Resources | 10 | 1.500 us/op | 0 B/op | 0/op |

#### Manager Transfer

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Transfer 100 Entities Between Managers | 10 | 10.500 us/op | 31.66 KiB/op | 6/op |
| Transfer 1000 Entities Between Managers | 10 | 95.300 us/op | 31.66 KiB/op | 6/op |
| Transfer 10000 Entities Between Managers | 10 | 1.031 ms/op | 31.66 KiB/op | 6/op |
| Transfer 100000 Entities Between Managers | 10 | 14.426 ms/op | 31.66 KiB/op | 6/op |
| Transfer 1000000 Entities Between Managers | 10 | 165.899 ms/op | 31.66 KiB/op | 6/op |

