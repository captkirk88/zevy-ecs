#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 7.100 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 78.150 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 735.900 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 8.089 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 86.228 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 2.650 us/op | 6.31 KiB/op | 3/op |
| Create 1000 Entities | 10 | 54.100 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 436.250 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.540 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 35.402 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 1.200 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 7.150 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 60.800 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 634.350 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.659 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 51.550 us/op | 103 B/op | 9/op |
| 1000 Entities, 3 Stages | 10 | 42.200 us/op | 103 B/op | 9/op |
| 10000 Entities, 3 Stages | 10 | 95.450 us/op | 103 B/op | 9/op |
| 100000 Entities, 3 Stages | 10 | 533.450 us/op | 103 B/op | 9/op |
| 1000000 Entities, 3 Stages | 10 | 5.319 ms/op | 103 B/op | 9/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 3.500 us/op | 13.27 KiB/op | 17/op |
| Run CRUD System on 1000 Entities | 10 | 21.750 us/op | 24.80 KiB/op | 17/op |
| Run CRUD System on 10000 Entities | 10 | 157.250 us/op | 125.49 KiB/op | 18/op |
| Run CRUD System on 100000 Entities | 10 | 2.176 ms/op | 1.57 MiB/op | 19/op |
| Run CRUD System on 1000000 Entities | 10 | 30.580 ms/op | 13.32 MiB/op | 19/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.200 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 11.000 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 108.750 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.204 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 11.649 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 264.650 us/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 438.300 us/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 4.133 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 10.748 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 108.045 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 51.250 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 164.750 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.445 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 14.496 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 146.669 ms/op | 0 B/op | 0/op |

#### Manager Transfer

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Transfer 100 Entities Between Managers | 10 | 10.750 us/op | 31.66 KiB/op | 6/op |
| Transfer 1000 Entities Between Managers | 10 | 100.550 us/op | 31.66 KiB/op | 6/op |
| Transfer 10000 Entities Between Managers | 10 | 1.068 ms/op | 31.66 KiB/op | 6/op |
| Transfer 100000 Entities Between Managers | 10 | 15.770 ms/op | 31.66 KiB/op | 6/op |
| Transfer 1000000 Entities Between Managers | 10 | 160.688 ms/op | 31.66 KiB/op | 6/op |

