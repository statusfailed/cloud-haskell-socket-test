{-# LANGUAGE OverloadedStrings #-}
module Main where

import Control.Exception.Base
import Control.Monad
import Control.Concurrent (threadDelay)
import Control.Monad (forever)
import Data.IORef (IORef(..), readIORef, newIORef, modifyIORef)

import Network.Transport (Transport(..))
import Network.Transport.TCP (createTransport, defaultTCPParameters)
import Control.Distributed.Process
import Control.Distributed.Process.Node

import qualified Data.ByteString as BS

import Network.Socket
  ( Socket(..), socket, bind, listen, accept
  , SocketType(..), SockAddr(..), setSocketOption, SocketOption(..)
  , Family(..), iNADDR_ANY
  )

import Network.Socket.ByteString as Socket (sendAll, recv)

recvBufSize :: Int
recvBufSize = 2048

-- | Listen for data from a child socket; broadcast all data to other children.
childReceiver :: IORef [ProcessId] -> Socket -> Process ()
childReceiver cref sock = do
  msg <- liftIO $ Socket.recv sock recvBufSize
  -- if msg is null, the socket was closed.
  unless (BS.null msg) $ do
    say $ "got message from child " ++ show sock
    children <- liftIO $ readIORef cref
    forM_ children (\pid -> send pid msg)
    childReceiver cref sock

-- | Listen for process messages and write to socket
childSender :: Socket -> Process ()
childSender sock = forever $ do
  msg <- expect :: Process BS.ByteString
  liftIO $ Socket.sendAll sock msg

-- | Spawn a pair of processes, reading and writing from a client socket connection
-- respectively.
-- The processes are linked, and will both die if one does.
spawnChild :: IORef [ProcessId] -> (Socket, SockAddr) -> Process ()
spawnChild cref (sock, _) = do
  senderPid <- spawnLocal $ do
    liftIO $ Socket.sendAll sock "welcome\n"
    childSender sock

  liftIO $ modifyIORef cref (\ps -> senderPid:ps)

  receiverPid <- spawnLocal $ do
    link senderPid -- pair child processes so both die together
    childReceiver cref sock

  return ()

-- | Main loop. Creates a socket, binds it to port 4444, and accepts
-- new connections. On connect, runs 'spawnChild'
listener :: IORef [ProcessId] -> Process ()
listener cref = do
  sock <- liftIO $ socket AF_INET Stream 0
  liftIO $ do
    setSocketOption sock ReuseAddr 1
    bind sock (SockAddrInet 4444 iNADDR_ANY)
    listen sock 4096 -- listen for up to 4K connections

  forever $ do
    conn <- liftIO $ accept sock
    say $ "listener got connection from " ++ show (snd conn)
    -- spawn process with connection
    spawnChild cref conn

-- | Create the CloudHaskell transport.
getTransport :: String -> String -> IO (Either IOException Transport)
getTransport hostname port =
  createTransport hostname port externalAddress defaultTCPParameters
  -- not quite sure what this function is really for...
  where externalAddress bindPort = (hostname, port)

main :: IO ()
main = do
  Right t <- getTransport "127.0.0.1" "10501"
  node    <- newLocalNode t initRemoteTable
  cref    <- newIORef []
  runProcess node $ listener cref
