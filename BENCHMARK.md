#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 7.800 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 106.400 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 775.950 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 7.925 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 85.676 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 2.500 us/op | 6.31 KiB/op | 3/op |
| Create 1000 Entities | 10 | 43.350 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 385.500 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.511 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 35.896 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 1.200 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 7.150 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 61.950 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 616.650 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.825 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 37.400 us/op | 7 B/op | 7/op |
| 1000 Entities, 3 Stages | 10 | 44.450 us/op | 7 B/op | 7/op |
| 10000 Entities, 3 Stages | 10 | 81.800 us/op | 7 B/op | 7/op |
| 100000 Entities, 3 Stages | 10 | 554.000 us/op | 7 B/op | 7/op |
| 1000000 Entities, 3 Stages | 10 | 5.587 ms/op | 7 B/op | 7/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 3.800 us/op | 13.27 KiB/op | 17/op |
| Run CRUD System on 1000 Entities | 10 | 18.500 us/op | 24.80 KiB/op | 17/op |
| Run CRUD System on 10000 Entities | 10 | 183.000 us/op | 125.50 KiB/op | 18/op |
| Run CRUD System on 100000 Entities | 10 | 2.063 ms/op | 1.57 MiB/op | 19/op |
| Run CRUD System on 1000000 Entities | 10 | 33.699 ms/op | 13.32 MiB/op | 19/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.150 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.600 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 106.350 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.086 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 11.313 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 375.300 us/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 2.265 ms/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 4.389 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 10.854 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 107.764 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 49.550 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 171.400 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.486 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 15.088 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 151.422 ms/op | 0 B/op | 0/op |

#### Resource Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 1 Resources | 10 | 100.000 ns/op | 0 B/op | 0/op |
| Serialize 2 Resources | 10 | 250.000 ns/op | 0 B/op | 0/op |
| Serialize 4 Resources | 10 | 550.000 ns/op | 0 B/op | 0/op |
| Serialize 6 Resources | 10 | 650.000 ns/op | 0 B/op | 0/op |
| Serialize 8 Resources | 10 | 850.000 ns/op | 0 B/op | 0/op |
| Serialize 10 Resources | 10 | 1.100 us/op | 0 B/op | 0/op |

#### Resource Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 1 Resources | 10 | 300.000 ns/op | 0 B/op | 0/op |
| Deserialize 2 Resources | 10 | 350.000 ns/op | 0 B/op | 0/op |
| Deserialize 4 Resources | 10 | 650.000 ns/op | 0 B/op | 0/op |
| Deserialize 6 Resources | 10 | 950.000 ns/op | 0 B/op | 0/op |
| Deserialize 8 Resources | 10 | 1.250 us/op | 0 B/op | 0/op |
| Deserialize 10 Resources | 10 | 1.550 us/op | 0 B/op | 0/op |

#### Manager Transfer

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Transfer 100 Entities Between Managers | 10 | 10.450 us/op | 31.66 KiB/op | 6/op |
| Transfer 1000 Entities Between Managers | 10 | 99.800 us/op | 31.66 KiB/op | 6/op |
| Transfer 10000 Entities Between Managers | 10 | 1.094 ms/op | 31.66 KiB/op | 6/op |
| Transfer 100000 Entities Between Managers | 10 | 16.061 ms/op | 31.66 KiB/op | 6/op |
| Transfer 1000000 Entities Between Managers | 10 | 166.682 ms/op | 31.66 KiB/op | 6/op |

