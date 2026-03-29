#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 9.210 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 72.760 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 732.860 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 7.279 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 76.397 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 5.940 us/op | 6.31 KiB/op | 3/op |
| Create 1000 Entities | 10 | 55.700 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 405.960 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.562 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 36.508 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 2.140 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 7.010 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 61.140 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 615.700 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.602 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 100.660 us/op | 119 B/op | 10/op |
| 1000 Entities, 3 Stages | 10 | 63.490 us/op | 119 B/op | 10/op |
| 10000 Entities, 3 Stages | 10 | 118.070 us/op | 119 B/op | 10/op |
| 100000 Entities, 3 Stages | 10 | 588.010 us/op | 119 B/op | 10/op |
| 1000000 Entities, 3 Stages | 10 | 5.651 ms/op | 119 B/op | 10/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 10.530 us/op | 13.27 KiB/op | 17/op |
| Run CRUD System on 1000 Entities | 10 | 22.970 us/op | 24.80 KiB/op | 17/op |
| Run CRUD System on 10000 Entities | 10 | 167.880 us/op | 125.49 KiB/op | 18/op |
| Run CRUD System on 100000 Entities | 10 | 1.763 ms/op | 1.57 MiB/op | 19/op |
| Run CRUD System on 1000000 Entities | 10 | 29.394 ms/op | 13.32 MiB/op | 19/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.230 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.410 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 102.720 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.076 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 10.770 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 1.045 ms/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 2.718 ms/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 4.340 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 11.019 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 112.255 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 60.440 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 178.600 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.419 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 14.585 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 145.477 ms/op | 0 B/op | 0/op |

#### Manager Transfer

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Transfer 100 Entities Between Managers | 10 | 12.880 us/op | 31.66 KiB/op | 6/op |
| Transfer 1000 Entities Between Managers | 10 | 104.560 us/op | 31.66 KiB/op | 6/op |
| Transfer 10000 Entities Between Managers | 10 | 1.107 ms/op | 31.66 KiB/op | 6/op |
| Transfer 100000 Entities Between Managers | 10 | 14.364 ms/op | 31.66 KiB/op | 6/op |
| Transfer 1000000 Entities Between Managers | 10 | 166.079 ms/op | 31.66 KiB/op | 6/op |

