## Observations

- random updates are possible but the system is not optimized for it.
- operations: create, delete, open, close, read, write, snapshot (copy a directory at low cost), record append (multiple clients append data to the same file concurently and atomically).
- architecture
    - one master
    - multiple chunkservers
- a file is split into equal size chunks, each chunck has a handle (GUID 64bit) assigned by the master.
- chunk size is 64MB
    - dependent on the size of the workloads
    - main disadvantage is the higher fragmentation if the workloads are small. You can't have multiple files in one chunk!
- tipically clients request for multiple chunks and cache the result for a given time.
- metadata: file namespace, mapping from files to chunks, location of replicas for each chunk
    - all this is stored by the master, but the chunk locations are not persisted.
    - chunckservers periodically get asked by the master what chunks they contain.
    - chunk version numbers are also stored.
- all metadata is stored in memory: <64Kb for each chunk, <64Kb for each file namespace.
    - metadata is persisted to disk using an operations log: it's replicated, has checkpoints to keep it small and ensure fast recovery.
- data corruption is detected by checksumming the chunk. So the master keeps checksums of chunks as well?
? applications create checkpoints of data. Or is the service exposing a checkpoint interface.
- appending is much more efficient and resiliant to failures than random writes.
- file -> multiple -> file regions -> multiple -> chunks
- file regions
    - states: consistent (all replicas have the same data), defined, undefined


## Terms, Components and Datastructures

* file
* chunk - a section of a file. The chunk size is a global sistem config (Eg. 64MB).
        - chunks have a version number and a handle (GUID 64bit).
* mutation - operation which changes the contents or metadata of a chunk
* file region - states: consistent/inconsistent, defined/undefined
* record

## How it works

### Lease mechanism±

### Network Optimizations
- to transfer data from primary replica to all other replicas, a chain of replicas is made and data flow sequentially from one to another. this way transfers are fast and all bandwidth is used.
