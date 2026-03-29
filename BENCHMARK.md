#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 10.540 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 94.610 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 929.290 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 8.252 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 78.688 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 4.530 us/op | 6.31 KiB/op | 3/op |
| Create 1000 Entities | 10 | 47.350 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 383.980 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.543 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 37.851 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 2.150 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 7.090 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 62.860 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 624.720 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 7.027 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 68.910 us/op | 119 B/op | 10/op |
| 1000 Entities, 3 Stages | 10 | 59.450 us/op | 119 B/op | 10/op |
| 10000 Entities, 3 Stages | 10 | 117.580 us/op | 119 B/op | 10/op |
| 100000 Entities, 3 Stages | 10 | 606.710 us/op | 119 B/op | 10/op |
| 1000000 Entities, 3 Stages | 10 | 5.629 ms/op | 119 B/op | 10/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 9.210 us/op | 13.27 KiB/op | 17/op |
| Run CRUD System on 1000 Entities | 10 | 21.540 us/op | 24.80 KiB/op | 17/op |
| Run CRUD System on 10000 Entities | 10 | 170.410 us/op | 125.49 KiB/op | 18/op |
| Run CRUD System on 100000 Entities | 10 | 1.851 ms/op | 1.57 MiB/op | 19/op |
| Run CRUD System on 1000000 Entities | 10 | 31.730 ms/op | 13.32 MiB/op | 19/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.220 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.740 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 107.220 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.087 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 11.087 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 904.840 us/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 2.633 ms/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 4.187 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 10.953 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 111.333 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 57.630 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 166.600 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.428 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 14.234 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 146.720 ms/op | 0 B/op | 0/op |

#### Manager Transfer

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Transfer 100 Entities Between Managers | 10 | 15.530 us/op | 31.66 KiB/op | 6/op |
| Transfer 1000 Entities Between Managers | 10 | 114.520 us/op | 31.66 KiB/op | 6/op |
| Transfer 10000 Entities Between Managers | 10 | 1.197 ms/op | 31.66 KiB/op | 6/op |
| Transfer 100000 Entities Between Managers | 10 | 15.443 ms/op | 31.66 KiB/op | 6/op |
| Transfer 1000000 Entities Between Managers | 10 | 169.926 ms/op | 31.66 KiB/op | 6/op |

