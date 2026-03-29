#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 8.730 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 75.890 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 751.970 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 7.426 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 77.974 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 5.880 us/op | 6.31 KiB/op | 3/op |
| Create 1000 Entities | 10 | 53.610 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 406.450 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.578 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 36.093 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 2.460 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 7.190 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 61.240 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 599.710 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.447 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 78.780 us/op | 119 B/op | 10/op |
| 1000 Entities, 3 Stages | 10 | 58.840 us/op | 119 B/op | 10/op |
| 10000 Entities, 3 Stages | 10 | 112.250 us/op | 119 B/op | 10/op |
| 100000 Entities, 3 Stages | 10 | 560.440 us/op | 119 B/op | 10/op |
| 1000000 Entities, 3 Stages | 10 | 5.184 ms/op | 119 B/op | 10/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 1.880 us/op | 1.24 KiB/op | 5/op |
| Run CRUD System on 1000 Entities | 10 | 4.540 us/op | 1.24 KiB/op | 5/op |
| Run CRUD System on 10000 Entities | 10 | 40.010 us/op | 1.24 KiB/op | 5/op |
| Run CRUD System on 100000 Entities | 10 | 428.150 us/op | 1.24 KiB/op | 5/op |
| Run CRUD System on 1000000 Entities | 10 | 4.200 ms/op | 1.24 KiB/op | 5/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.400 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.480 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 105.220 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.079 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 10.771 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 1.433 ms/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 2.598 ms/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 4.173 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 10.950 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 112.315 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 58.810 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 178.320 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.495 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 15.078 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 150.990 ms/op | 0 B/op | 0/op |

#### Manager Transfer

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Transfer 100 Entities Between Managers | 10 | 16.270 us/op | 31.66 KiB/op | 6/op |
| Transfer 1000 Entities Between Managers | 10 | 103.710 us/op | 31.66 KiB/op | 6/op |
| Transfer 10000 Entities Between Managers | 10 | 1.046 ms/op | 31.66 KiB/op | 6/op |
| Transfer 100000 Entities Between Managers | 10 | 12.916 ms/op | 31.66 KiB/op | 6/op |
| Transfer 1000000 Entities Between Managers | 10 | 165.018 ms/op | 31.66 KiB/op | 6/op |

