{-# LANGUAGE GeneralizedNewtypeDeriving, TypeFamilies,
  DuplicateRecordFields, FlexibleInstances, DeriveFunctor #-}

module Language.Docker.Syntax where

import Data.List (intercalate, isInfixOf)
import Data.List.NonEmpty (NonEmpty)
import Data.List.Split (endBy)
import Data.String (IsString(..))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time.Clock (DiffTime)
import GHC.Exts (IsList(..))

data Image = Image
    { registryName :: !(Maybe Registry)
    , imageName :: !Text
    } deriving (Show, Eq, Ord)

instance IsString Image where
    fromString img =
        if "/" `isInfixOf` img
            then let parts = endBy "/" img
                 in case parts of
                        reg:rest ->
                            Image
                                (Just (Registry (Text.pack reg)))
                                (Text.pack . intercalate "/" $ rest)
                        _ -> Image Nothing (Text.pack img)
            else Image Nothing (Text.pack img)

newtype Registry = Registry
    { unRegistry :: Text
    } deriving (Show, Eq, Ord, IsString)

newtype Tag = Tag
    { unTag :: Text
    } deriving (Show, Eq, Ord, IsString)

data Protocol
    = TCP
    | UDP
    deriving (Show, Eq, Ord)

data Port
    = Port !Int
           !Protocol
    | PortStr !Text
    | PortRange !Int
                !Int
                !Protocol
    deriving (Show, Eq, Ord)

newtype Ports = Ports
    { unPorts :: [Port]
    } deriving (Show, Eq, Ord)

instance IsList Ports where
    type Item Ports = Port
    fromList = Ports
    toList (Ports ps) = ps

type Directory = Text

newtype ImageAlias = ImageAlias
    { unImageAlias :: Text
    } deriving (Show, Eq, Ord, IsString)

data BaseImage
    = UntaggedImage !Image
                    !(Maybe ImageAlias)
    | TaggedImage !Image
                  !Tag
                  !(Maybe ImageAlias)
    | DigestedImage !Image
                    !Text
                    !(Maybe ImageAlias)
    deriving (Eq, Ord, Show)

-- | Type of the Dockerfile AST
type Dockerfile = [InstructionPos Text]

newtype SourcePath = SourcePath
    { unSourcePath :: Text
    } deriving (Show, Eq, Ord, IsString)

newtype TargetPath = TargetPath
    { unTargetPath :: Text
    } deriving (Show, Eq, Ord, IsString)

data Chown
    = Chown !Text
    | NoChown
    deriving (Show, Eq, Ord)

instance IsString Chown where
    fromString ch =
        case ch of
            "" -> NoChown
            _ -> Chown (Text.pack ch)

data CopySource
    = CopySource !Text
    | NoSource
    deriving (Show, Eq, Ord)

instance IsString CopySource where
    fromString src =
        case src of
            "" -> NoSource
            _ -> CopySource (Text.pack src)

newtype Duration = Duration
    { durationTime :: DiffTime
    } deriving (Show, Eq, Ord, Num)

newtype Retries = Retries
    { times :: Int
    } deriving (Show, Eq, Ord, Num)

data CopyArgs = CopyArgs
    { sourcePaths :: NonEmpty SourcePath
    , targetPath :: !TargetPath
    , chownFlag :: !Chown
    , sourceFlag :: !CopySource
    } deriving (Show, Eq, Ord)

data AddArgs = AddArgs
    { sourcePaths :: NonEmpty SourcePath
    , targetPath :: !TargetPath
    , chownFlag :: !Chown
    } deriving (Show, Eq, Ord)

data Check args
    = Check !(CheckArgs args)
    | NoCheck
    deriving (Show, Eq, Ord, Functor)

data Arguments args
    = ArgumentsText args
    | ArgumentsList args
    deriving (Show, Eq, Ord, Functor)

instance IsString (Arguments Text) where
    fromString = ArgumentsText . Text.pack

instance IsList (Arguments Text) where
    type Item (Arguments Text) = Text
    fromList = ArgumentsList . Text.unwords
    toList (ArgumentsText ps) = Text.words ps
    toList (ArgumentsList ps) = Text.words ps

data CheckArgs args = CheckArgs
    { checkCommand :: !(Arguments args)
    , interval :: !(Maybe Duration)
    , timeout :: !(Maybe Duration)
    , startPeriod :: !(Maybe Duration)
    , retries :: !(Maybe Retries)
    } deriving (Show, Eq, Ord, Functor)

type Pairs = [(Text, Text)]

-- | All commands available in Dockerfiles
data Instruction args
    = From !BaseImage
    | Add !AddArgs
    | User !Text
    | Label !Pairs
    | Stopsignal !Text
    | Copy !CopyArgs
    | Run !(Arguments args)
    | Cmd !(Arguments args)
    | Shell !(Arguments args)
    | Workdir !Directory
    | Expose !Ports
    | Volume !Text
    | Entrypoint !(Arguments args)
    | Maintainer !Text
    | Env !Pairs
    | Arg !Text
          !(Maybe Text)
    | Healthcheck !(Check args)
    | Comment !Text
    | OnBuild !(Instruction args)
    deriving (Eq, Ord, Show, Functor)

type Filename = Text

type Linenumber = Int

-- | 'Instruction' with additional location information required for creating
-- good check messages
data InstructionPos args = InstructionPos
    { instruction :: !(Instruction args)
    , sourcename :: !Filename
    , lineNumber :: !Linenumber
    } deriving (Eq, Ord, Show, Functor)
