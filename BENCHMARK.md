#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 8.400 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 80.500 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 784.600 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 7.947 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 85.814 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 2.650 us/op | 6.32 KiB/op | 3/op |
| Create 1000 Entities | 10 | 41.350 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 423.800 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.650 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 35.776 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 1.300 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 7.350 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 61.550 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 645.100 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.926 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 21.300 us/op | 7 B/op | 7/op |
| 1000 Entities, 3 Stages | 10 | 31.500 us/op | 7 B/op | 7/op |
| 10000 Entities, 3 Stages | 10 | 100.700 us/op | 7 B/op | 7/op |
| 100000 Entities, 3 Stages | 10 | 523.050 us/op | 7 B/op | 7/op |
| 1000000 Entities, 3 Stages | 10 | 5.867 ms/op | 7 B/op | 7/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 4.500 us/op | 13.30 KiB/op | 17/op |
| Run CRUD System on 1000 Entities | 10 | 21.100 us/op | 24.83 KiB/op | 18/op |
| Run CRUD System on 10000 Entities | 10 | 163.900 us/op | 125.53 KiB/op | 18/op |
| Run CRUD System on 100000 Entities | 10 | 2.334 ms/op | 1.57 MiB/op | 19/op |
| Run CRUD System on 1000000 Entities | 10 | 40.029 ms/op | 13.32 MiB/op | 20/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.200 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.900 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 107.600 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.086 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 11.203 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 271.550 us/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 319.550 us/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 5.431 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 11.612 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 119.090 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 53.200 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 169.400 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.462 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 14.841 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 151.148 ms/op | 0 B/op | 0/op |

#### Resource Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 1 Resources | 10 | 200.000 ns/op | 0 B/op | 0/op |
| Serialize 2 Resources | 10 | 300.000 ns/op | 0 B/op | 0/op |
| Serialize 4 Resources | 10 | 400.000 ns/op | 0 B/op | 0/op |
| Serialize 6 Resources | 10 | 550.000 ns/op | 0 B/op | 0/op |
| Serialize 8 Resources | 10 | 850.000 ns/op | 0 B/op | 0/op |
| Serialize 10 Resources | 10 | 1.050 us/op | 0 B/op | 0/op |

#### Resource Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 1 Resources | 10 | 150.000 ns/op | 0 B/op | 0/op |
| Deserialize 2 Resources | 10 | 350.000 ns/op | 0 B/op | 0/op |
| Deserialize 4 Resources | 10 | 650.000 ns/op | 0 B/op | 0/op |
| Deserialize 6 Resources | 10 | 850.000 ns/op | 0 B/op | 0/op |
| Deserialize 8 Resources | 10 | 1.150 us/op | 0 B/op | 0/op |
| Deserialize 10 Resources | 10 | 1.600 us/op | 0 B/op | 0/op |

#### Manager Transfer

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Transfer 100 Entities Between Managers | 10 | 10.800 us/op | 31.70 KiB/op | 7/op |
| Transfer 1000 Entities Between Managers | 10 | 105.400 us/op | 31.70 KiB/op | 7/op |
| Transfer 10000 Entities Between Managers | 10 | 1.141 ms/op | 31.70 KiB/op | 7/op |
| Transfer 100000 Entities Between Managers | 10 | 17.057 ms/op | 31.70 KiB/op | 7/op |
| Transfer 1000000 Entities Between Managers | 10 | 172.237 ms/op | 31.70 KiB/op | 7/op |

