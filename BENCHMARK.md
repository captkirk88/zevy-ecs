#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 6.800 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 83.450 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 769.900 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 8.154 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 88.234 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 2.950 us/op | 6.32 KiB/op | 3/op |
| Create 1000 Entities | 10 | 42.900 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 414.650 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.226 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 35.490 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 1.300 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 7.200 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 60.550 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 611.050 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.780 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 24.450 us/op | 7 B/op | 7/op |
| 1000 Entities, 3 Stages | 10 | 27.100 us/op | 7 B/op | 7/op |
| 10000 Entities, 3 Stages | 10 | 72.300 us/op | 7 B/op | 7/op |
| 100000 Entities, 3 Stages | 10 | 526.150 us/op | 7 B/op | 7/op |
| 1000000 Entities, 3 Stages | 10 | 5.736 ms/op | 7 B/op | 7/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 4.850 us/op | 13.28 KiB/op | 17/op |
| Run CRUD System on 1000 Entities | 10 | 19.450 us/op | 24.82 KiB/op | 18/op |
| Run CRUD System on 10000 Entities | 10 | 160.400 us/op | 125.52 KiB/op | 18/op |
| Run CRUD System on 100000 Entities | 10 | 2.219 ms/op | 1.57 MiB/op | 19/op |
| Run CRUD System on 1000000 Entities | 10 | 33.225 ms/op | 13.32 MiB/op | 20/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.200 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.450 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 105.150 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.054 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 10.830 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 188.550 us/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 334.900 us/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 4.891 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 10.649 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 106.128 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 50.700 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 168.000 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.425 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 14.297 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 145.538 ms/op | 0 B/op | 0/op |

#### Resource Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 1 Resources | 10 | 200.000 ns/op | 0 B/op | 0/op |
| Serialize 2 Resources | 10 | 250.000 ns/op | 0 B/op | 0/op |
| Serialize 4 Resources | 10 | 400.000 ns/op | 0 B/op | 0/op |
| Serialize 6 Resources | 10 | 550.000 ns/op | 0 B/op | 0/op |
| Serialize 8 Resources | 10 | 750.000 ns/op | 0 B/op | 0/op |
| Serialize 10 Resources | 10 | 2.200 us/op | 0 B/op | 0/op |

#### Resource Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 1 Resources | 10 | 150.000 ns/op | 0 B/op | 0/op |
| Deserialize 2 Resources | 10 | 350.000 ns/op | 0 B/op | 0/op |
| Deserialize 4 Resources | 10 | 650.000 ns/op | 0 B/op | 0/op |
| Deserialize 6 Resources | 10 | 850.000 ns/op | 0 B/op | 0/op |
| Deserialize 8 Resources | 10 | 1.150 us/op | 0 B/op | 0/op |
| Deserialize 10 Resources | 10 | 1.450 us/op | 0 B/op | 0/op |

#### Manager Transfer

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Transfer 100 Entities Between Managers | 10 | 11.250 us/op | 31.70 KiB/op | 7/op |
| Transfer 1000 Entities Between Managers | 10 | 110.950 us/op | 31.70 KiB/op | 7/op |
| Transfer 10000 Entities Between Managers | 10 | 1.129 ms/op | 31.70 KiB/op | 7/op |
| Transfer 100000 Entities Between Managers | 10 | 16.912 ms/op | 31.70 KiB/op | 7/op |
| Transfer 1000000 Entities Between Managers | 10 | 171.783 ms/op | 31.70 KiB/op | 7/op |

