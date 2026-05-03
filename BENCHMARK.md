#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 7.850 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 78.650 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 739.150 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 8.032 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 83.502 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 2.650 us/op | 6.31 KiB/op | 3/op |
| Create 1000 Entities | 10 | 46.650 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 429.100 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.578 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 35.683 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 1.150 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 7.000 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 61.150 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 632.500 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.596 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 44.450 us/op | 7 B/op | 7/op |
| 1000 Entities, 3 Stages | 10 | 51.050 us/op | 7 B/op | 7/op |
| 10000 Entities, 3 Stages | 10 | 87.700 us/op | 7 B/op | 7/op |
| 100000 Entities, 3 Stages | 10 | 492.750 us/op | 7 B/op | 7/op |
| 1000000 Entities, 3 Stages | 10 | 5.387 ms/op | 7 B/op | 7/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 4.200 us/op | 13.27 KiB/op | 17/op |
| Run CRUD System on 1000 Entities | 10 | 21.050 us/op | 24.80 KiB/op | 17/op |
| Run CRUD System on 10000 Entities | 10 | 171.650 us/op | 125.50 KiB/op | 18/op |
| Run CRUD System on 100000 Entities | 10 | 2.210 ms/op | 1.57 MiB/op | 19/op |
| Run CRUD System on 1000000 Entities | 10 | 33.237 ms/op | 13.32 MiB/op | 19/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.200 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.450 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 106.300 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.077 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 11.245 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 558.100 us/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 2.152 ms/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 4.361 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 12.212 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 113.785 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 75.900 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 271.050 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.490 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 15.394 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 146.071 ms/op | 0 B/op | 0/op |

#### Resource Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 1 Resources | 10 | 150.000 ns/op | 0 B/op | 0/op |
| Serialize 2 Resources | 10 | 400.000 ns/op | 0 B/op | 0/op |
| Serialize 4 Resources | 10 | 350.000 ns/op | 0 B/op | 0/op |
| Serialize 6 Resources | 10 | 600.000 ns/op | 0 B/op | 0/op |
| Serialize 8 Resources | 10 | 850.000 ns/op | 0 B/op | 0/op |
| Serialize 10 Resources | 10 | 1.050 us/op | 0 B/op | 0/op |

#### Resource Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 1 Resources | 10 | 150.000 ns/op | 0 B/op | 0/op |
| Deserialize 2 Resources | 10 | 300.000 ns/op | 0 B/op | 0/op |
| Deserialize 4 Resources | 10 | 600.000 ns/op | 0 B/op | 0/op |
| Deserialize 6 Resources | 10 | 850.000 ns/op | 0 B/op | 0/op |
| Deserialize 8 Resources | 10 | 1.150 us/op | 0 B/op | 0/op |
| Deserialize 10 Resources | 10 | 1.500 us/op | 0 B/op | 0/op |

#### Manager Transfer

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Transfer 100 Entities Between Managers | 10 | 10.000 us/op | 31.66 KiB/op | 6/op |
| Transfer 1000 Entities Between Managers | 10 | 98.600 us/op | 31.66 KiB/op | 6/op |
| Transfer 10000 Entities Between Managers | 10 | 1.079 ms/op | 31.66 KiB/op | 6/op |
| Transfer 100000 Entities Between Managers | 10 | 13.953 ms/op | 31.66 KiB/op | 6/op |
| Transfer 1000000 Entities Between Managers | 10 | 168.511 ms/op | 31.66 KiB/op | 6/op |

