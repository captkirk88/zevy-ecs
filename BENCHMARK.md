#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 6.900 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 70.650 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 676.100 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 7.998 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 82.997 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 3.000 us/op | 6.31 KiB/op | 3/op |
| Create 1000 Entities | 10 | 46.350 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 432.250 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.462 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 35.270 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 1.200 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 6.950 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 61.750 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 672.350 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.534 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 47.300 us/op | 103 B/op | 9/op |
| 1000 Entities, 3 Stages | 10 | 46.350 us/op | 103 B/op | 9/op |
| 10000 Entities, 3 Stages | 10 | 102.650 us/op | 103 B/op | 9/op |
| 100000 Entities, 3 Stages | 10 | 541.300 us/op | 103 B/op | 9/op |
| 1000000 Entities, 3 Stages | 10 | 5.553 ms/op | 103 B/op | 9/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 3.800 us/op | 13.27 KiB/op | 17/op |
| Run CRUD System on 1000 Entities | 10 | 19.450 us/op | 24.80 KiB/op | 17/op |
| Run CRUD System on 10000 Entities | 10 | 157.850 us/op | 125.50 KiB/op | 18/op |
| Run CRUD System on 100000 Entities | 10 | 2.102 ms/op | 1.57 MiB/op | 19/op |
| Run CRUD System on 1000000 Entities | 10 | 31.574 ms/op | 13.32 MiB/op | 19/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.200 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.750 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 104.300 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.069 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 11.038 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 227.400 us/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 2.560 ms/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 4.477 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 10.651 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 105.987 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 50.200 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 165.000 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.420 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 14.388 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 144.175 ms/op | 0 B/op | 0/op |

#### Resource Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 1 Resources | 10 | 250.000 ns/op | 0 B/op | 0/op |
| Serialize 2 Resources | 10 | 300.000 ns/op | 0 B/op | 0/op |
| Serialize 4 Resources | 10 | 850.000 ns/op | 0 B/op | 0/op |
| Serialize 6 Resources | 10 | 600.000 ns/op | 0 B/op | 0/op |
| Serialize 8 Resources | 10 | 850.000 ns/op | 0 B/op | 0/op |
| Serialize 10 Resources | 10 | 1.000 us/op | 0 B/op | 0/op |

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
| Transfer 100 Entities Between Managers | 10 | 10.500 us/op | 31.66 KiB/op | 6/op |
| Transfer 1000 Entities Between Managers | 10 | 99.650 us/op | 31.66 KiB/op | 6/op |
| Transfer 10000 Entities Between Managers | 10 | 1.066 ms/op | 31.66 KiB/op | 6/op |
| Transfer 100000 Entities Between Managers | 10 | 13.567 ms/op | 31.66 KiB/op | 6/op |
| Transfer 1000000 Entities Between Managers | 10 | 160.436 ms/op | 31.66 KiB/op | 6/op |

