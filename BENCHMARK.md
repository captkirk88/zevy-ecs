#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 8.100 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 75.250 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 843.500 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 7.990 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 86.579 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 2.600 us/op | 6.32 KiB/op | 3/op |
| Create 1000 Entities | 10 | 38.150 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 362.150 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.183 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 33.236 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 1.250 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 7.000 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 88.400 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 651.300 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.872 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 42.850 us/op | 7 B/op | 7/op |
| 1000 Entities, 3 Stages | 10 | 45.700 us/op | 7 B/op | 7/op |
| 10000 Entities, 3 Stages | 10 | 87.150 us/op | 7 B/op | 7/op |
| 100000 Entities, 3 Stages | 10 | 491.900 us/op | 7 B/op | 7/op |
| 1000000 Entities, 3 Stages | 10 | 5.630 ms/op | 7 B/op | 7/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 5.600 us/op | 13.28 KiB/op | 17/op |
| Run CRUD System on 1000 Entities | 10 | 18.750 us/op | 24.82 KiB/op | 18/op |
| Run CRUD System on 10000 Entities | 10 | 168.700 us/op | 125.52 KiB/op | 18/op |
| Run CRUD System on 100000 Entities | 10 | 2.118 ms/op | 1.57 MiB/op | 19/op |
| Run CRUD System on 1000000 Entities | 10 | 33.026 ms/op | 13.32 MiB/op | 20/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.300 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.700 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 106.350 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.135 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 11.295 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 464.100 us/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 552.900 us/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 5.022 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 11.006 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 110.150 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 49.650 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 172.250 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.483 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 15.096 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 150.476 ms/op | 0 B/op | 0/op |

#### Resource Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 1 Resources | 10 | 200.000 ns/op | 0 B/op | 0/op |
| Serialize 2 Resources | 10 | 250.000 ns/op | 0 B/op | 0/op |
| Serialize 4 Resources | 10 | 400.000 ns/op | 0 B/op | 0/op |
| Serialize 6 Resources | 10 | 550.000 ns/op | 0 B/op | 0/op |
| Serialize 8 Resources | 10 | 800.000 ns/op | 0 B/op | 0/op |
| Serialize 10 Resources | 10 | 1.000 us/op | 0 B/op | 0/op |

#### Resource Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 1 Resources | 10 | 300.000 ns/op | 0 B/op | 0/op |
| Deserialize 2 Resources | 10 | 300.000 ns/op | 0 B/op | 0/op |
| Deserialize 4 Resources | 10 | 550.000 ns/op | 0 B/op | 0/op |
| Deserialize 6 Resources | 10 | 900.000 ns/op | 0 B/op | 0/op |
| Deserialize 8 Resources | 10 | 1.150 us/op | 0 B/op | 0/op |
| Deserialize 10 Resources | 10 | 1.500 us/op | 0 B/op | 0/op |

#### Manager Transfer

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Transfer 100 Entities Between Managers | 10 | 10.200 us/op | 31.70 KiB/op | 7/op |
| Transfer 1000 Entities Between Managers | 10 | 101.000 us/op | 31.70 KiB/op | 7/op |
| Transfer 10000 Entities Between Managers | 10 | 1.136 ms/op | 31.70 KiB/op | 7/op |
| Transfer 100000 Entities Between Managers | 10 | 17.049 ms/op | 31.70 KiB/op | 7/op |
| Transfer 1000000 Entities Between Managers | 10 | 177.326 ms/op | 31.70 KiB/op | 7/op |

