#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 9.690 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 76.090 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 763.870 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 7.630 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 80.666 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 5.110 us/op | 6.31 KiB/op | 3/op |
| Create 1000 Entities | 10 | 39.270 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 442.260 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.763 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 37.773 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 2.070 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 7.230 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 61.010 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 605.790 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.611 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| 100 Entities, 3 Stages | 10 | 69.130 us/op | 103 B/op | 9/op |
| 1000 Entities, 3 Stages | 10 | 59.680 us/op | 103 B/op | 9/op |
| 10000 Entities, 3 Stages | 10 | 97.670 us/op | 103 B/op | 9/op |
| 100000 Entities, 3 Stages | 10 | 555.740 us/op | 103 B/op | 9/op |
| 1000000 Entities, 3 Stages | 10 | 5.621 ms/op | 103 B/op | 9/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 8.900 us/op | 13.27 KiB/op | 17/op |
| Run CRUD System on 1000 Entities | 10 | 21.920 us/op | 24.80 KiB/op | 17/op |
| Run CRUD System on 10000 Entities | 10 | 178.110 us/op | 125.49 KiB/op | 18/op |
| Run CRUD System on 100000 Entities | 10 | 1.883 ms/op | 1.57 MiB/op | 19/op |
| Run CRUD System on 1000000 Entities | 10 | 31.265 ms/op | 13.32 MiB/op | 19/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.290 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.840 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 105.840 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.083 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 11.053 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 1.734 ms/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 1.145 ms/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 3.953 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 11.530 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 110.121 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 60.470 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 170.210 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.426 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 14.393 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 146.266 ms/op | 0 B/op | 0/op |

#### Manager Transfer

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Transfer 100 Entities Between Managers | 10 | 14.520 us/op | 31.66 KiB/op | 6/op |
| Transfer 1000 Entities Between Managers | 10 | 108.090 us/op | 31.66 KiB/op | 6/op |
| Transfer 10000 Entities Between Managers | 10 | 1.129 ms/op | 31.66 KiB/op | 6/op |
| Transfer 100000 Entities Between Managers | 10 | 13.246 ms/op | 31.66 KiB/op | 6/op |
| Transfer 1000000 Entities Between Managers | 10 | 162.301 ms/op | 31.66 KiB/op | 6/op |

