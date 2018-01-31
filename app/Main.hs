module Main where

import Control.Exception.Base (IOException)
import Control.Concurrent (threadDelay)
import Control.Monad (forever)
import Control.Distributed.Process
import Control.Distributed.Process.Node
import Network.Transport.TCP (createTransport, defaultTCPParameters)
import Network.Transport (Transport(..))

-- Tutorial code from
-- http://haskell-distributed.github.io/tutorials/1ch.html
-- NOTE: modified to add the "transport" function, because the
-- type of 'createTransport' has changed.

replyBack :: (ProcessId, String) -> Process ()
replyBack (sender, msg) = send sender msg

logMessage :: String -> Process ()
logMessage msg = say $ "handling " ++ msg

transport :: String -> String -> IO (Either IOException Transport)
transport hostname port =
  createTransport hostname port externalAddress defaultTCPParameters
  -- not quite sure what this function is really for...
  where externalAddress bindPort = (hostname, port)

main :: IO ()
main = do
  Right t <- transport "127.0.0.1" "10501"
  node <- newLocalNode t initRemoteTable
  runProcess node $ do
    -- Spawn another worker on the local node
    echoPid <- spawnLocal $ forever $ do
      -- Test our matches in order against each message in the queue
      receiveWait [match logMessage, match replyBack]

    -- The `say` function sends a message to a process registered as "logger".
    -- By default, this process simply loops through its mailbox and sends
    -- any received log message strings it finds to stderr.

    say "send some messages!"
    send echoPid "hello"
    self <- getSelfPid
    send echoPid (self, "hello")

    -- `expectTimeout` waits for a message or times out after "delay"
    m <- expectTimeout 1000000
    case m of
      -- Die immediately - throws a ProcessExitException with the given reason.
      Nothing  -> die "nothing came back!"
      Just s -> say $ "got " ++ s ++ " back!"

    -- Without the following delay, the process sometimes exits before the
    -- messages are exchanged.
    liftIO $ threadDelay 2000000
