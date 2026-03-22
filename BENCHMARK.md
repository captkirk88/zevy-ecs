#### Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 9.140 us/op | 4.07 KiB/op | 1/op |
| Create 1000 Entities | 10 | 74.530 us/op | 4.07 KiB/op | 1/op |
| Create 10000 Entities | 10 | 734.520 us/op | 4.07 KiB/op | 1/op |
| Create 100000 Entities | 10 | 8.031 ms/op | 4.07 KiB/op | 1/op |
| Create 1000000 Entities | 10 | 82.180 ms/op | 4.07 KiB/op | 1/op |

#### Batch Creation

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Create 100 Entities | 10 | 4.040 us/op | 6.31 KiB/op | 3/op |
| Create 1000 Entities | 10 | 45.030 us/op | 26.53 KiB/op | 3/op |
| Create 10000 Entities | 10 | 445.560 us/op | 228.68 KiB/op | 3/op |
| Create 100000 Entities | 10 | 3.735 ms/op | 2.20 MiB/op | 3/op |
| Create 1000000 Entities | 10 | 38.078 ms/op | 21.94 MiB/op | 3/op |

#### Mixed Systems

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run 7 Systems on 100 Entities | 10 | 1.660 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000 Entities | 10 | 6.910 us/op | 7 B/op | 7/op |
| Run 7 Systems on 10000 Entities | 10 | 61.100 us/op | 7 B/op | 7/op |
| Run 7 Systems on 100000 Entities | 10 | 607.030 us/op | 7 B/op | 7/op |
| Run 7 Systems on 1000000 Entities | 10 | 6.516 ms/op | 7 B/op | 7/op |

#### Scheduler

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run Scheduler Stage on 100 Entities | 10 | 79.490 us/op | 295 B/op | 8/op |
| Run Scheduler Stage on 1000 Entities | 10 | 66.800 us/op | 295 B/op | 8/op |
| Run Scheduler Stage on 10000 Entities | 10 | 70.560 us/op | 295 B/op | 8/op |
| Run Scheduler Stage on 100000 Entities | 10 | 263.570 us/op | 295 B/op | 8/op |
| Run Scheduler Stage on 1000000 Entities | 10 | 2.341 ms/op | 295 B/op | 8/op |

#### CRUD System

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Run CRUD System on 100 Entities | 10 | 4.020 us/op | 12.31 KiB/op | 7/op |
| Run CRUD System on 1000 Entities | 10 | 24.140 us/op | 20.71 KiB/op | 8/op |
| Run CRUD System on 10000 Entities | 10 | 160.390 us/op | 90.00 KiB/op | 8/op |
| Run CRUD System on 100000 Entities | 10 | 1.756 ms/op | 1.23 MiB/op | 9/op |
| Run CRUD System on 1000000 Entities | 10 | 19.930 ms/op | 9.91 MiB/op | 10/op |

#### Relations

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Scene Graph 100 Entities | 10 | 1.210 us/op | 49 B/op | 2/op |
| Scene Graph 1000 Entities | 10 | 10.490 us/op | 49 B/op | 2/op |
| Scene Graph 10000 Entities | 10 | 104.900 us/op | 49 B/op | 2/op |
| Scene Graph 100000 Entities | 10 | 1.062 ms/op | 49 B/op | 2/op |
| Scene Graph 1000000 Entities | 10 | 10.818 ms/op | 49 B/op | 2/op |

#### Serialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Serialize 100 Entities | 10 | 936.890 us/op | 0 B/op | 0/op |
| Serialize 1000 Entities | 10 | 2.336 ms/op | 0 B/op | 0/op |
| Serialize 10000 Entities | 10 | 3.897 ms/op | 0 B/op | 0/op |
| Serialize 100000 Entities | 10 | 11.393 ms/op | 0 B/op | 0/op |
| Serialize 1000000 Entities | 10 | 111.637 ms/op | 0 B/op | 0/op |

#### Deserialization

| Benchmark | Operations | Time/op | Memory/op | Allocs/op
|-----------|------------|---------|----------|----------|
| Deserialize 100 Entities | 10 | 60.180 us/op | 0 B/op | 0/op |
| Deserialize 1000 Entities | 10 | 183.500 us/op | 0 B/op | 0/op |
| Deserialize 10000 Entities | 10 | 1.571 ms/op | 0 B/op | 0/op |
| Deserialize 100000 Entities | 10 | 16.065 ms/op | 0 B/op | 0/op |
| Deserialize 1000000 Entities | 10 | 159.755 ms/op | 0 B/op | 0/op |

