# cloud-haskell-socket-test

A "chat" server using the distributed-process family of libraries.
It really just sends bytestreams from each client to all other clients.
Not very smart!

## Install

    stack build
    stack exec cloud-haskell-socket-test-exe

## Use

Connect and send/receive bytes to/from other clients:

    nc localhost 4444

# How it works

* Single thread accepting new connections, spawns a new local process on
  client connect.
* Client thread is actually a pair of processes, both have an IORef containing
  Pids of all other processes:
  1. Reader: reads msgs from client, and broadcasts to other processes
  2. Writer: receives raw strings from other clients and writes to socket
