#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 5.400 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 92.150 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 757.700 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 7.739 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 85.283 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 2.750 us/op | 6.32 KiB/op | 3/op |
| Create 1000 Entities | 10 | 45.400 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 440.050 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 4.041 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 34.782 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 1.250 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 6.950 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 61.550 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 611.300 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.753 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 23.750 us/op | 7 B/op | 7/op |
| 1000 Entities, 3 Stages | 10 | 27.900 us/op | 7 B/op | 7/op |
| 10000 Entities, 3 Stages | 10 | 72.100 us/op | 7 B/op | 7/op |
| 100000 Entities, 3 Stages | 10 | 530.200 us/op | 7 B/op | 7/op |
| 1000000 Entities, 3 Stages | 10 | 5.923 ms/op | 7 B/op | 7/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 4.650 us/op | 13.30 KiB/op | 17/op |
| Run CRUD System on 1000 Entities | 10 | 21.500 us/op | 24.83 KiB/op | 18/op |
| Run CRUD System on 10000 Entities | 10 | 179.550 us/op | 125.53 KiB/op | 18/op |
| Run CRUD System on 100000 Entities | 10 | 2.239 ms/op | 1.57 MiB/op | 19/op |
| Run CRUD System on 1000000 Entities | 10 | 28.987 ms/op | 13.32 MiB/op | 20/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.250 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.700 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 108.400 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.093 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 11.155 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 397.650 us/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 434.900 us/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 5.143 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 10.704 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 107.033 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 55.250 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 170.900 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.427 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 14.345 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 146.343 ms/op | 0 B/op | 0/op |

#### Resource Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 1 Resources | 10 | 150.000 ns/op | 0 B/op | 0/op |
| Serialize 2 Resources | 10 | 300.000 ns/op | 0 B/op | 0/op |
| Serialize 4 Resources | 10 | 500.000 ns/op | 0 B/op | 0/op |
| Serialize 6 Resources | 10 | 650.000 ns/op | 0 B/op | 0/op |
| Serialize 8 Resources | 10 | 800.000 ns/op | 0 B/op | 0/op |
| Serialize 10 Resources | 10 | 1.000 us/op | 0 B/op | 0/op |

#### Resource Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 1 Resources | 10 | 150.000 ns/op | 0 B/op | 0/op |
| Deserialize 2 Resources | 10 | 600.000 ns/op | 0 B/op | 0/op |
| Deserialize 4 Resources | 10 | 600.000 ns/op | 0 B/op | 0/op |
| Deserialize 6 Resources | 10 | 850.000 ns/op | 0 B/op | 0/op |
| Deserialize 8 Resources | 10 | 1.750 us/op | 0 B/op | 0/op |
| Deserialize 10 Resources | 10 | 1.600 us/op | 0 B/op | 0/op |

#### Manager Transfer

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Transfer 100 Entities Between Managers | 10 | 10.850 us/op | 31.70 KiB/op | 7/op |
| Transfer 1000 Entities Between Managers | 10 | 121.200 us/op | 31.70 KiB/op | 7/op |
| Transfer 10000 Entities Between Managers | 10 | 1.206 ms/op | 31.70 KiB/op | 7/op |
| Transfer 100000 Entities Between Managers | 10 | 17.265 ms/op | 31.70 KiB/op | 7/op |
| Transfer 1000000 Entities Between Managers | 10 | 166.570 ms/op | 31.70 KiB/op | 7/op |

