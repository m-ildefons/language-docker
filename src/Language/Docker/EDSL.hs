{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE TemplateHaskell #-}

module Language.Docker.EDSL where

import Control.Monad.Free
import Control.Monad.Free.TH
import Control.Monad.Trans.Free (FreeT, iterTM)
import Control.Monad.Writer
import Data.ByteString (ByteString)
import Data.List.NonEmpty (NonEmpty)
import Data.String (fromString)

import qualified Language.Docker.PrettyPrint as PrettyPrint
import qualified Language.Docker.Syntax as Syntax

import Language.Docker.EDSL.Types

-- | The type of 'Identity' based EDSL blocks
type EDockerfileM = Free EInstruction

-- | The type of free monad EDSL blocks
type EDockerfileTM = FreeT EInstruction

type EInstructionM = Free EInstruction

type EInstructionTM = FreeT EInstruction

makeFree ''EInstruction

runDockerWriter :: (MonadWriter [Syntax.Instruction] m) => EDockerfileM a -> m a
runDockerWriter = iterM runD

runDockerWriterIO ::
       (Monad m, MonadTrans t, Monad (t m), MonadWriter [Syntax.Instruction] (t m), MonadIO (t m))
    => EDockerfileTM m a
    -> t m a
runDockerWriterIO = iterTM runD

runDef :: MonadWriter [t] m => (t1 -> t) -> t1 -> m b -> m b
runDef f a n = tell [f a] >> n

runDef2 :: MonadWriter [t] m => (t1 -> t2 -> t) -> t1 -> t2 -> m b -> m b
runDef2 f a b n = tell [f a b] >> n

runD :: MonadWriter [Syntax.Instruction] m => EInstruction (m b) -> m b
runD (From bi n) =
    case bi of
        EUntaggedImage bi' alias -> runDef Syntax.From (Syntax.UntaggedImage bi' alias) n
        ETaggedImage bi' tg alias -> runDef Syntax.From (Syntax.TaggedImage bi' tg alias) n
        EDigestedImage bi' d alias -> runDef Syntax.From (Syntax.DigestedImage bi' d alias) n
runD (CmdArgs as n) = runDef Syntax.Cmd as n
runD (Shell as n) = runDef Syntax.Shell as n
runD (AddArgs s d c n) = runDef Syntax.Add (Syntax.AddArgs s d c) n
runD (User u n) = runDef Syntax.User u n
runD (Label ps n) = runDef Syntax.Label ps n
runD (StopSignal s n) = runDef Syntax.Stopsignal s n
runD (CopyArgs s d c f n) = runDef Syntax.Copy (Syntax.CopyArgs s d c f) n
runD (RunArgs as n) = runDef Syntax.Run as n
runD (Workdir d n) = runDef Syntax.Workdir d n
runD (Expose ps n) = runDef Syntax.Expose ps n
runD (Volume v n) = runDef Syntax.Volume v n
runD (EntrypointArgs e n) = runDef Syntax.Entrypoint e n
runD (Maintainer m n) = runDef Syntax.Maintainer m n
runD (Env ps n) = runDef Syntax.Env ps n
runD (Arg k v n) = runDef2 Syntax.Arg k v n
runD (Comment c n) = runDef Syntax.Comment c n
runD (Healthcheck c n) = runDef Syntax.Healthcheck c n
runD (OnBuildRaw i n) = runDef Syntax.OnBuild i n
runD (Embed is n) = do
    tell (map Syntax.instruction is)
    n

instructionPos :: Syntax.Instruction -> Syntax.InstructionPos
instructionPos i = Syntax.InstructionPos i "" 0

-- | Runs the Dockerfile EDSL and returns a 'Dockerfile' you can pretty print
-- or manipulate
toDockerfile :: EDockerfileM a -> Syntax.Dockerfile
toDockerfile e =
    let (_, w) = runWriter (runDockerWriter e)
    in map instructionPos w

-- | runs the Dockerfile EDSL and returns a 'String' using
-- 'Language.Docker.PrettyPrint'
--
-- @
-- import Language.Docker
--
-- main :: IO ()
-- main = writeFile "something.dockerfile" $ toDockerfileStr $ do
--     from (tagged "fpco/stack-build" "lts-6.9")
--     add ["."] "/app/language-docker"
--     workdir "/app/language-docker"
--     run "stack build --test --only-dependencies"
--     cmd "stack test"
-- @
toDockerfileStr :: EDockerfileM a -> String
toDockerfileStr = PrettyPrint.prettyPrint . toDockerfile

untagged :: String -> EBaseImage
untagged = flip EUntaggedImage Nothing . fromString

tagged :: Syntax.Image -> String -> EBaseImage
tagged imageName tag = ETaggedImage imageName tag Nothing

digested :: Syntax.Image -> ByteString -> EBaseImage
digested imageName hash = EDigestedImage imageName hash Nothing

aliased :: EBaseImage -> String -> EBaseImage
aliased image alias =
    case image of
        EUntaggedImage n _ -> EUntaggedImage n (Just $ Syntax.ImageAlias alias)
        ETaggedImage n t _ -> ETaggedImage n t (Just $ Syntax.ImageAlias alias)
        EDigestedImage n h _ -> EDigestedImage n h (Just $ Syntax.ImageAlias alias)

ports :: [Syntax.Port] -> Syntax.Ports
ports = Syntax.Ports

tcpPort :: Integer -> Syntax.Port
tcpPort = flip Syntax.Port Syntax.TCP

udpPort :: Integer -> Syntax.Port
udpPort = flip Syntax.Port Syntax.UDP

variablePort :: String -> Syntax.Port
variablePort varName = Syntax.PortStr ('$' : varName)

portRange :: Integer -> Integer -> Syntax.Port
portRange = Syntax.PortRange

run :: MonadFree EInstruction m => Syntax.Arguments -> m ()
run = runArgs

entrypoint :: MonadFree EInstruction m => Syntax.Arguments -> m ()
entrypoint = entrypointArgs

cmd :: MonadFree EInstruction m => Syntax.Arguments -> m ()
cmd = cmdArgs

copy :: MonadFree EInstruction m => Syntax.CopyArgs -> m ()
copy (Syntax.CopyArgs sources dest ch src) = copyArgs sources dest ch src

copyFromStage ::
       MonadFree EInstruction m
    => Syntax.CopySource
    -> NonEmpty Syntax.SourcePath
    -> Syntax.TargetPath
    -> m ()
copyFromStage stage source dest = copy $ Syntax.CopyArgs source dest Syntax.NoChown stage

add :: MonadFree EInstruction m => NonEmpty Syntax.SourcePath -> Syntax.TargetPath -> m ()
add sources dest = addArgs sources dest Syntax.NoChown

toSources :: NonEmpty String -> NonEmpty Syntax.SourcePath
toSources = fmap Syntax.SourcePath

toTarget :: String -> Syntax.TargetPath
toTarget = Syntax.TargetPath

fromStage :: Syntax.CopyArgs -> Syntax.CopySource -> Syntax.CopyArgs
fromStage args src = args {Syntax.sourceFlag = src}

ownedBy :: Syntax.CopyArgs -> Syntax.Chown -> Syntax.CopyArgs
ownedBy args owner = args {Syntax.chownFlag = owner}

to :: NonEmpty Syntax.SourcePath -> Syntax.TargetPath -> Syntax.CopyArgs
to sources dest = Syntax.CopyArgs sources dest Syntax.NoChown Syntax.NoSource

check :: Syntax.Arguments -> Syntax.Check
check command =
    Syntax.Check
        Syntax.CheckArgs
        { Syntax.checkCommand = command
        , Syntax.interval = Nothing
        , Syntax.timeout = Nothing
        , Syntax.startPeriod = Nothing
        , Syntax.retries = Nothing
        }

interval :: Syntax.Check -> Integer -> Syntax.Check
interval ch secs =
    case ch of
        Syntax.NoCheck -> Syntax.NoCheck
        Syntax.Check chArgs -> Syntax.Check chArgs {Syntax.interval = Just $ fromInteger secs}

timeout :: Syntax.Check -> Integer -> Syntax.Check
timeout ch secs =
    case ch of
        Syntax.NoCheck -> Syntax.NoCheck
        Syntax.Check chArgs -> Syntax.Check chArgs {Syntax.timeout = Just $ fromInteger secs}

startPeriod :: Syntax.Check -> Integer -> Syntax.Check
startPeriod ch secs =
    case ch of
        Syntax.NoCheck -> Syntax.NoCheck
        Syntax.Check chArgs -> Syntax.Check chArgs {Syntax.startPeriod = Just $ fromInteger secs}

retries :: Syntax.Check -> Integer -> Syntax.Check
retries ch tries =
    case ch of
        Syntax.NoCheck -> Syntax.NoCheck
        Syntax.Check chArgs -> Syntax.Check chArgs {Syntax.retries = Just $ fromInteger tries}

noCheck :: Syntax.Check
noCheck = Syntax.NoCheck

-- | ONBUILD Dockerfile instruction
--
-- Each nested instruction gets emitted as a separate @ONBUILD@ block
--
-- @
-- 'toDockerfile' $ do
--     from "node"
--     run "apt-get update"
--     onBuild $ do
--         run "echo more-stuff"
--         run "echo here"
-- @
onBuild :: MonadFree EInstruction m => EDockerfileM a -> m ()
onBuild b = mapM_ (onBuildRaw . Syntax.instruction) (toDockerfile b)

-- | A version of 'toDockerfile' which allows IO actions
toDockerfileIO :: MonadIO m => EDockerfileTM m t -> m Syntax.Dockerfile
toDockerfileIO e = fmap snd (runDockerfileIO e)

-- | A version of 'toDockerfileStr' which allows IO actions
toDockerfileStrIO :: MonadIO m => EDockerfileTM m t -> m String
toDockerfileStrIO e = fmap snd (runDockerfileStrIO e)

-- | Just runs the EDSL's writer monad
runDockerfileIO :: MonadIO m => EDockerfileTM m t -> m (t, Syntax.Dockerfile)
runDockerfileIO e = do
    (r, w) <- runWriterT (runDockerWriterIO e)
    return (r, map instructionPos w)

-- | Runs the EDSL's writer monad and pretty-prints the result
runDockerfileStrIO :: MonadIO m => EDockerfileTM m t -> m (t, String)
runDockerfileStrIO e = do
    (r, w) <- runDockerfileIO e
    return (r, PrettyPrint.prettyPrint w)
