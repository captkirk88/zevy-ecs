#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 7.400 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 74.350 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 686.350 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 8.077 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 82.782 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 3.150 us/op | 6.32 KiB/op | 3/op |
| Create 1000 Entities | 10 | 63.900 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 440.500 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.407 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 35.754 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 1.200 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 7.150 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 60.100 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 602.800 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.576 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 35.000 us/op | 7 B/op | 7/op |
| 1000 Entities, 3 Stages | 10 | 26.700 us/op | 7 B/op | 7/op |
| 10000 Entities, 3 Stages | 10 | 78.700 us/op | 7 B/op | 7/op |
| 100000 Entities, 3 Stages | 10 | 601.450 us/op | 7 B/op | 7/op |
| 1000000 Entities, 3 Stages | 10 | 5.849 ms/op | 7 B/op | 7/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 3.750 us/op | 13.30 KiB/op | 17/op |
| Run CRUD System on 1000 Entities | 10 | 20.150 us/op | 24.83 KiB/op | 18/op |
| Run CRUD System on 10000 Entities | 10 | 157.000 us/op | 125.53 KiB/op | 18/op |
| Run CRUD System on 100000 Entities | 10 | 2.372 ms/op | 1.57 MiB/op | 19/op |
| Run CRUD System on 1000000 Entities | 10 | 31.797 ms/op | 13.32 MiB/op | 20/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.250 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.600 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 106.700 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.074 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 11.760 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 194.750 us/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 2.936 ms/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 5.960 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 10.853 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 111.416 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 85.350 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 193.300 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.454 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 14.275 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 145.110 ms/op | 0 B/op | 0/op |

#### Resource Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 1 Resources | 10 | 100.000 ns/op | 0 B/op | 0/op |
| Serialize 2 Resources | 10 | 300.000 ns/op | 0 B/op | 0/op |
| Serialize 4 Resources | 10 | 400.000 ns/op | 0 B/op | 0/op |
| Serialize 6 Resources | 10 | 600.000 ns/op | 0 B/op | 0/op |
| Serialize 8 Resources | 10 | 800.000 ns/op | 0 B/op | 0/op |
| Serialize 10 Resources | 10 | 1.050 us/op | 0 B/op | 0/op |

#### Resource Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 1 Resources | 10 | 200.000 ns/op | 0 B/op | 0/op |
| Deserialize 2 Resources | 10 | 350.000 ns/op | 0 B/op | 0/op |
| Deserialize 4 Resources | 10 | 700.000 ns/op | 0 B/op | 0/op |
| Deserialize 6 Resources | 10 | 950.000 ns/op | 0 B/op | 0/op |
| Deserialize 8 Resources | 10 | 1.750 us/op | 0 B/op | 0/op |
| Deserialize 10 Resources | 10 | 1.550 us/op | 0 B/op | 0/op |

#### Manager Transfer

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Transfer 100 Entities Between Managers | 10 | 10.850 us/op | 31.70 KiB/op | 7/op |
| Transfer 1000 Entities Between Managers | 10 | 106.550 us/op | 31.70 KiB/op | 7/op |
| Transfer 10000 Entities Between Managers | 10 | 1.098 ms/op | 31.70 KiB/op | 7/op |
| Transfer 100000 Entities Between Managers | 10 | 14.682 ms/op | 31.70 KiB/op | 7/op |
| Transfer 1000000 Entities Between Managers | 10 | 174.690 ms/op | 31.70 KiB/op | 7/op |

