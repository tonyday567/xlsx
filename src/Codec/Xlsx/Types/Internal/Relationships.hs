{-# LANGUAGE CPP               #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
module Codec.Xlsx.Types.Internal.Relationships where

import           Data.List                  (find)
import           Data.Map                   (Map)
import qualified Data.Map                   as Map
import           Data.Monoid                ((<>))
import           Data.Text                  (Text)
import qualified Data.Text                  as T
import           Network.URI                hiding (path)
import           Prelude                    hiding (abs, lookup)
import           Safe
import           Text.XML
import           Text.XML.Cursor

#if !MIN_VERSION_base(4,8,0)
import           Control.Applicative
#endif

import           Codec.Xlsx.Parser.Internal
import           Codec.Xlsx.Types.Internal
import           Codec.Xlsx.Writer.Internal

data Relationship = Relationship
    { relType   :: Text
    , relTarget :: FilePath
    } deriving (Eq, Show, Generic)

-- | Describes relationships according to Open Packaging Convention
--
-- See ECMA-376, 4th Edition Office Open XML File Formats — Open Packaging
-- Conventions
newtype Relationships = Relationships
    { relMap :: Map RefId Relationship
    } deriving (Eq, Show, Generic)

fromList :: [(RefId, Relationship)] -> Relationships
fromList = Relationships . Map.fromList

empty :: Relationships
empty = fromList []

size :: Relationships -> Int
size = Map.size . relMap

relEntry :: RefId -> Text -> FilePath -> (RefId, Relationship)
relEntry rId typ trg = (rId, Relationship (stdRelType typ) trg)

lookup :: RefId -> Relationships -> Maybe Relationship
lookup ref = Map.lookup ref . relMap

setTargetsFrom :: FilePath -> Relationships -> Relationships
setTargetsFrom fp (Relationships m) = Relationships (Map.map fixPath m)
    where
        fixPath rel = rel{ relTarget = fp `joinRel` relTarget rel}

-- | joins relative URI (actually a file path as an internal relation target)
joinRel :: FilePath -> FilePath -> FilePath
joinRel abs rel = uriToString id (relPath `nonStrictRelativeTo` base) ""
  where
    base = fromJustNote "joinRel base path" $ parseURIReference abs
    relPath = fromJustNote "joinRel relative path" $ parseURIReference rel

relFrom :: FilePath -> FilePath -> FilePath
relFrom path base = uriToString id (pathURI `relativeFrom` baseURI) ""
  where
    baseURI = fromJustNote "joinRel base path" $ parseURIReference base
    pathURI = fromJustNote "joinRel relative path" $ parseURIReference path

findRelByType :: Text -> Relationships -> Maybe Relationship
findRelByType t (Relationships m) = find ((==t) . relType) (Map.elems m)

allByType :: Text -> Relationships -> [Relationship]
allByType t (Relationships m) = filter ((==t) . relType) (Map.elems m)

{-------------------------------------------------------------------------------
  Rendering
-------------------------------------------------------------------------------}

instance ToDocument Relationships where
  toDocument = documentFromNsElement "Relationships generated by xlsx" pkgRelNs
               . toElement "Relationships"

instance ToElement Relationships where
  toElement nm Relationships{..} = Element
      { elementName       = nm
      , elementAttributes = Map.empty
      , elementNodes      = map (NodeElement . relToEl "Relationship") $
                            Map.toList relMap
      }
    where
      relToEl nm' (relId, rel) = setAttr "Id" relId (toElement nm' rel)

instance ToElement Relationship where
  toElement nm Relationship{..} = Element
      { elementName       = nm
      , elementAttributes = Map.fromList [ "Target" .= relTarget
                                         , "Type"   .= relType ]
      , elementNodes      = []
      }

{-------------------------------------------------------------------------------
  Parsing
-------------------------------------------------------------------------------}
instance FromCursor Relationships where
  fromCursor cur = do
    let items = cur $/ element (pr"Relationship") >=> parseRelEntry
    return . Relationships $ Map.fromList items

parseRelEntry :: Cursor -> [(RefId, Relationship)]
parseRelEntry cur = do
  rel <- fromCursor cur
  rId <- attribute "Id" cur
  return (RefId rId, rel)

instance FromCursor Relationship where
  fromCursor cur =  do
    ty <- attribute "Type" cur
    trg <- T.unpack <$> attribute "Target" cur
    return $ Relationship ty trg

-- | Add package relationship namespace to name
pr :: Text -> Name
pr x = Name
  { nameLocalName = x
  , nameNamespace = Just pkgRelNs
  , namePrefix = Nothing
  }

-- | Add office document relationship namespace to name
odr :: Text -> Name
odr x = Name
  { nameLocalName = x
  , nameNamespace = Just odRelNs
  , namePrefix = Nothing
  }

odRelNs :: Text
odRelNs = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

pkgRelNs :: Text
pkgRelNs = "http://schemas.openxmlformats.org/package/2006/relationships"

stdRelType :: Text -> Text
stdRelType t = stdPart <> t
  where
    stdPart = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
