{-# LANGUAGE TemplateHaskell #-}

module Language.Docker.Syntax.Lift where

import qualified Data.ByteString as ByteString
import Data.Fixed (Fixed)
import Data.Time.Clock (DiffTime)
import Language.Haskell.TH.Lift
import Language.Haskell.TH.Syntax ()

import Language.Docker.Syntax

instance Lift ByteString.ByteString where
    lift b = [|ByteString.pack $(lift $ ByteString.unpack b)|]

deriveLift ''Fixed

deriveLift ''DiffTime

deriveLift ''Protocol

deriveLift ''Port

deriveLift ''Ports

deriveLift ''Registry

deriveLift ''Image

deriveLift ''ImageAlias

deriveLift ''Tag

deriveLift ''Digest

deriveLift ''BaseImage

deriveLift ''Arguments

deriveLift ''Instruction

deriveLift ''InstructionPos

deriveLift ''SourcePath

deriveLift ''TargetPath

deriveLift ''Chown

deriveLift ''CopySource

deriveLift ''CopyArgs

deriveLift ''AddArgs

deriveLift ''Duration

deriveLift ''Retries

deriveLift ''CheckArgs

deriveLift ''Check
