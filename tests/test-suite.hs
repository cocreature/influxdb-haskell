{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
import Control.Applicative
import Control.Exception as E
import Control.Monad.Trans
import Data.Int
import Data.List (find)
import Data.Monoid
import Data.Text (Text)
import Data.Unique
import Data.Word
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Vector as V

import Test.Tasty.HUnit
import Test.Tasty.TH
import Test.Tasty.QuickCheck hiding (reason)
import qualified Network.HTTP.Client as HC

import Database.InfluxDB
import Database.InfluxDB.TH
import qualified Database.InfluxDB.Stream as S

prop_fromValue_toValue_identity_Value :: Value -> Bool
prop_fromValue_toValue_identity_Value = fromValueToValueIdentity

prop_fromValue_toValue_identity_Bool :: Bool -> Bool
prop_fromValue_toValue_identity_Bool = fromValueToValueIdentity

prop_fromValue_toValue_identity_Int :: Int -> Bool
prop_fromValue_toValue_identity_Int = fromValueToValueIdentity

prop_fromValue_toValue_identity_Int8 :: Int8 -> Bool
prop_fromValue_toValue_identity_Int8 = fromValueToValueIdentity

prop_fromValue_toValue_identity_Int16 :: Int16 -> Bool
prop_fromValue_toValue_identity_Int16 = fromValueToValueIdentity

prop_fromValue_toValue_identity_Int32 :: Int32 -> Bool
prop_fromValue_toValue_identity_Int32 = fromValueToValueIdentity

prop_fromValue_toValue_identity_Int64 :: Int64 -> Bool
prop_fromValue_toValue_identity_Int64 = fromValueToValueIdentity

prop_fromValue_toValue_identity_Word8 :: Word8 -> Bool
prop_fromValue_toValue_identity_Word8 = fromValueToValueIdentity

prop_fromValue_toValue_identity_Word16 :: Word16 -> Bool
prop_fromValue_toValue_identity_Word16 = fromValueToValueIdentity

prop_fromValue_toValue_identity_Word32 :: Word32 -> Bool
prop_fromValue_toValue_identity_Word32 = fromValueToValueIdentity

prop_fromValue_toValue_identity_Double :: Double -> Bool
prop_fromValue_toValue_identity_Double = fromValueToValueIdentity

prop_fromValue_toValue_identity_Text :: T.Text -> Bool
prop_fromValue_toValue_identity_Text = fromValueToValueIdentity

prop_fromValue_toValue_identity_LazyText :: TL.Text -> Bool
prop_fromValue_toValue_identity_LazyText = fromValueToValueIdentity

prop_fromValue_toValue_identity_String :: String -> Bool
prop_fromValue_toValue_identity_String = fromValueToValueIdentity

prop_fromValue_toValue_identity_Maybe_Int :: Maybe Int -> Bool
prop_fromValue_toValue_identity_Maybe_Int = fromValueToValueIdentity

-------------------------------------------------

instance Arbitrary Value where
  arbitrary = oneof
    [ Int <$> arbitrary
    , Float <$> arbitrary
    , String <$> arbitrary
    , Bool <$> arbitrary
    , pure Null
    ]

instance Arbitrary T.Text where
  arbitrary = T.pack <$> arbitrary

instance Arbitrary TL.Text where
  arbitrary = TL.pack <$> arbitrary

fromValueToValueIdentity :: (Eq a, FromValue a, ToValue a) => a -> Bool
fromValueToValueIdentity a = fromValue (toValue a) == Right a

-------------------------------------------------

case_ping :: Assertion
case_ping = runTest $ \config -> do
  Ping status <- ping config
  status @?= "ok"

case_isInSync :: Assertion
case_isInSync = runTest $ \config -> do
  inSync <- isInSync config
  assertBool "The database is not in sync." inSync

case_post :: Assertion
case_post = runTest $ \config ->
  withTestDatabase config $ \database -> do
    name <- liftIO newName
    post config database $
      writeSeries name $ Val 42
    ss <- query config database $ "select value from " <> name
    case ss of
      [series] -> fromSeriesData series @?= Right [Val 42]
      _ -> assertFailure $ "Expect one series, but got: " ++ show ss

case_post_multi_series :: Assertion
case_post_multi_series = runTest $ \config ->
  withTestDatabase config $ \database -> do
    name <- liftIO newName
    post config database $ do
      writeSeries name $ Val 42
      writeSeries name $ Val 42
      writeSeries name $ Val 42
    ss <- query config database $ "select value from " <> name
    case ss of
      [series] -> fromSeriesData series @?= Right [Val 42, Val 42, Val 42]
      _ -> assertFailure $ "Expect one series, but got: " ++ show ss

case_post_multi_points :: Assertion
case_post_multi_points = runTest $ \config ->
  withTestDatabase config $ \database -> do
    name <- liftIO newName
    post config database $ withSeries name $ do
      writePoints $ Val 42
      writePoints $ Val 42
      writePoints $ Val 42
    ss <- query config database $ "select value from " <> name
    case ss of
      [series] -> fromSeriesData series @?= Right [Val 42, Val 42, Val 42]
      _ -> assertFailure $ "Expect one series, but got: " ++ show ss

case_query_nonexistent_series :: Assertion
case_query_nonexistent_series = runTest $ \config ->
  withTestDatabase config $ \database -> do
    name <- liftIO newName
    assertStatusCodeException
      (query config database $ "select * from " <> name :: IO [SeriesData])

case_query_empty_series :: Assertion
case_query_empty_series = runTest $ \config ->
  withTestDatabase config $ \database -> do
    name <- liftIO newName
    post config database $
      writeSeries name $ Val 42
    ss1 <- query config database $ "delete from " <> name
    ss1 @?= ([] :: [SeriesData])
    ss2 <- query config database $ "select * from " <> name
    ss2 @?= ([] :: [SeriesData])

case_queryChunked :: Assertion
case_queryChunked = runTest $ \config ->
  withTestDatabase config $ \database -> do
    name <- liftIO newName
    post config database $ withSeries name $ do
      writePoints $ Val 42
      writePoints $ Val 42
      writePoints $ Val 42
    ss <- queryChunked config database ("select value from " <> name) $
      S.fold step []
    mapM fromSeriesData ss @?= Right [[Val 42], [Val 42], [Val 42]]
  where
    step xs series = case fromSeriesData series of
      Left reason -> throwIO $ HUnitFailure reason
      Right values -> return $ xs ++ values

case_post_with_precision :: Assertion
case_post_with_precision = runTest $ \config ->
  withTestDatabase config $ \database -> do
    name <- liftIO newName
    postWithPrecision config database SecondsPrecision $
      writeSeries name $ Val 42
    ss <- query config database $ "select value from " <> name
    case ss of
      [series] -> fromSeriesData series @?= Right [Val 42]
      _ -> assertFailure $ "Expect one series, but got: " ++ show ss

case_delete_series :: Assertion
case_delete_series = runTest $ \config ->
  withTestDatabase config $ \database -> do
    name <- liftIO newName
    post config database $
      writeSeries name $ Val 42
    ss <- query config database $ "select value from " <> name
    case ss of
      [series] -> fromSeriesData series @?= Right [Val 42]
      _ -> assertFailure $ "Expect one series, but got: " ++ show ss
    deleteSeries config database name
    assertStatusCodeException
      (query config database $ "select value from " <> name :: IO [SeriesData])

case_listDatabases :: Assertion
case_listDatabases = runTest $ \config ->
  withTestDatabase config $ \name -> do
    databases <- listDatabases config
    assertBool ("No such database: " ++ T.unpack name) $
      any ((name ==) . databaseName) databases

case_configureDatabase :: Assertion
case_configureDatabase = runTest $ \config -> do
  dbName <- newName
  do
    configureDatabase config dbName $ DatabaseRequest shardSpaces contQueries
    listDatabases config >>= \databases ->
      assertBool ("No such database: " ++ T.unpack dbName) $
        any ((dbName ==) . databaseName) databases
    listShardSpaces config >>= \spaces ->
        assertBool "Missing shard space(s)" $
          any ((`elem` spaceNames) . shardSpaceName) spaces
    `finally`
      dropDatabase config dbName
  where
    spaceNames = map shardSpaceRequestName shardSpaces
    shardSpaces =
      [ ShardSpaceRequest
          { shardSpaceRequestName = "everything_30d"
          , shardSpaceRequestRetentionPolicy = "30d"
          , shardSpaceRequestShardDuration = "7d"
          , shardSpaceRequestRegex = "/.*/"
          , shardSpaceRequestReplicationFactor = 1
          , shardSpaceRequestSplit = 1
          }
      , ShardSpaceRequest
          { shardSpaceRequestName = "forever"
          , shardSpaceRequestRetentionPolicy = "inf"
          , shardSpaceRequestShardDuration = "7d"
          , shardSpaceRequestRegex = "/^_.*/"
          , shardSpaceRequestReplicationFactor = 1
          , shardSpaceRequestSplit = 1
          }
      , ShardSpaceRequest
          { shardSpaceRequestName = "rollups"
          , shardSpaceRequestRetentionPolicy = "365d"
          , shardSpaceRequestShardDuration = "30d"
          , shardSpaceRequestRegex = "/^\\d+.*/"
          , shardSpaceRequestReplicationFactor = 1
          , shardSpaceRequestSplit = 1
          }
      ]
    contQueries =
      [ "select * from events into events.[id]"
      , "select count(value) from events group by time(5m) into 5m.count.events"
      ]

case_shardSpaces :: Assertion
case_shardSpaces = runTest $ \config ->
  withTestDatabase config $ \name -> do
    spaceName <- newName
    createShardSpace config name $ ShardSpaceRequest
      { shardSpaceRequestName = spaceName
      , shardSpaceRequestRegex = "^[a-z].*"
      , shardSpaceRequestRetentionPolicy = "7d"
      , shardSpaceRequestShardDuration = "1d"
      , shardSpaceRequestReplicationFactor = 1
      , shardSpaceRequestSplit = 1
      }
    listShardSpaces config >>= \spaces ->
      assertBool ("No such shard space: " ++ T.unpack spaceName) $
        any ((spaceName ==) . shardSpaceName) spaces
    dropShardSpace config name spaceName
    listShardSpaces config >>= \spaces ->
      assertBool ("Found a dropped shard space: " ++ T.unpack spaceName) $
        all ((spaceName /=) . shardSpaceName) spaces

case_create_then_drop_database :: Assertion
case_create_then_drop_database = runTest $ \config -> do
  name <- newName
  dropDatabaseIfExists config name
  createDatabase config name
  listDatabases config >>= \databases ->
    assertBool ("No such database: " ++ T.unpack name) $
      any ((name ==) . databaseName) databases
  dropDatabase config name
  listDatabases config >>= \databases ->
    assertBool ("Found a dropped database: " ++ T.unpack name) $
      all ((name /=) . databaseName) databases

case_list_cluster_admins :: Assertion
case_list_cluster_admins = runTest $ \config -> do
  admins <- listClusterAdmins config
  assertBool "No root admin" $
    any (("root" ==) . adminName) admins

case_authenticate_cluster_admin :: Assertion
case_authenticate_cluster_admin = runTest authenticateClusterAdmin

case_add_then_delete_cluster_admin :: Assertion
case_add_then_delete_cluster_admin = runTest $ \config -> do
  name <- newName
  admin <- addClusterAdmin config name "somePassword"
  listClusterAdmins config >>= \admins ->
    assertBool ("No such admin: " ++ T.unpack name) $
      any ((name ==) . adminName) admins
  deleteClusterAdmin config admin
  listClusterAdmins config >>= \admins ->
    assertBool ("Found a deleted admin: " ++ T.unpack name) $
      all ((name /=) . adminName) admins

case_update_cluster_admin_password :: Assertion
case_update_cluster_admin_password = runTest $ \config -> do
  let curPassword = "somePassword"
      newPassword = "otherPassword"
  name <- newName
  deleteClusterAdminIfExists config name
  admin <- addClusterAdmin config name curPassword
  updateClusterAdminPassword config admin newPassword
  let newCreds = Credentials name newPassword
      newConfig = config { configCreds = newCreds }
  name' <- newName
  dropDatabaseIfExists config name'
  createDatabase newConfig name'
  listDatabases newConfig >>= \databases ->
    assertBool ("No such database: " ++ T.unpack name') $
      any ((name' ==) . databaseName) databases
  dropDatabase newConfig name'
  listDatabases newConfig >>= \databases ->
    assertBool ("Found a dropped database: " ++ T.unpack name') $
      all ((name' /=) . databaseName) databases
  deleteClusterAdmin config admin

case_add_then_delete_database_users :: Assertion
case_add_then_delete_database_users = runTest $ \config ->
  withTestDatabase config $ \name -> do
    listDatabaseUsers config name >>= \users ->
      assertBool "There shouldn't be any users" $ null users
    newUserName <- newName
    addDatabaseUser config name newUserName "somePassword"
    let newCreds = rootCreds
          { credsUser = newUserName
          , credsPassword = "somePassword" }
        newConfig = config { configCreds = newCreds }
    authenticateDatabaseUser newConfig name
    listDatabaseUsers config name >>= \users ->
      assertBool ("No such user: " <> T.unpack newUserName) $
        any ((newUserName ==) . userName) users
    deleteDatabaseUser config name newUserName
    listDatabaseUsers config name >>= \users ->
      assertBool ("Found a deleted user: " <> T.unpack newUserName) $
        all ((newUserName /=) . userName) users

case_update_database_user_password :: Assertion
case_update_database_user_password = runTest $ \config ->
  withTestDatabase config $ \name -> do
    newUserName <- newName
    addDatabaseUser config name newUserName "somePassword"
    listDatabaseUsers config name >>= \users ->
      assertBool ("No such user: " <> T.unpack newUserName) $
        any ((newUserName ==) . userName) users
    updateDatabaseUserPassword config name newUserName "otherPassword"
    deleteDatabaseUser config name newUserName

case_grant_revoke_database_user :: Assertion
case_grant_revoke_database_user = runTest $ \config ->
  withTestDatabase config $ \name -> do
    newUserName <- newName
    addDatabaseUser config name newUserName "somePassword"
    listDatabaseUsers config name >>= \users ->
      assertBool ("No such user: " <> T.unpack newUserName) $
        any ((newUserName ==) . userName) users
    grantAdminPrivilegeTo config name newUserName
    listDatabaseUsers config name >>= \users ->
      case find ((newUserName ==) . userName) users of
        Nothing -> assertFailure $ "No such user: " <> T.unpack newUserName
        Just user -> assertBool
          ("User is not privileged: " <> T.unpack newUserName)
          (userIsAdmin user)
    revokeAdminPrivilegeFrom config name newUserName
    listDatabaseUsers config name >>= \users ->
      case find ((newUserName ==) . userName) users of
        Nothing -> assertFailure $ "No such user: " <> T.unpack newUserName
        Just user -> assertBool
          ("User is still privileged: " <> T.unpack newUserName)
          (not $ userIsAdmin user)
    deleteDatabaseUser config name newUserName

-------------------------------------------------
-- Regressions

newtype WholeFloat = WholeFloat
  { wholeFloatValue :: Double
  } deriving (Eq, Show)

-- #14: InfluxDB may return Int instead of Float when
-- the WholeFloat value happens to be a whole number.
case_regression_whole_Float_number :: Assertion
case_regression_whole_Float_number = runTest $ \config ->
  withTestDatabase config $ \database -> do
    series <- newName
    post config database $
      writeSeries series $ WholeFloat 42.0
    ss <- query config database $ "select value from " <> series
    case ss of
      [sd] -> fromSeriesData sd @?= Right [WholeFloat 42]
      _ -> assertFailure $ "Expect one series, but got: " ++ show ss

case_regression_really_big_Float_number :: Assertion
case_regression_really_big_Float_number = runTest $ \config ->
  withTestDatabase config $ \database -> do
    series <- newName
    post config database $
      writeSeries series $ WholeFloat 42e100
    ss <- query config database $ "select value from " <> series
    case ss of
      [sd] -> fromSeriesData sd @?= Right [WholeFloat 42e100]
      _ -> assertFailure $ "Expect one series, but got: " ++ show ss

-------------------------------------------------

data Val = Val Int deriving (Eq, Show)

instance ToSeriesData Val where
  toSeriesColumns _ = V.fromList ["value"]
  toSeriesPoints (Val n) = V.fromList [toValue n]

instance FromSeriesData Val where
  parseSeriesData = withValues $ \values -> Val <$> values .: "value"

-------------------------------------------------

dropDatabaseIfExists :: Config -> Text -> IO ()
dropDatabaseIfExists config name =
  dropDatabase config name
    `catchAll` \_ -> return ()

deleteClusterAdminIfExists :: Config -> Text -> IO ()
deleteClusterAdminIfExists config name =
  deleteClusterAdmin config (Admin name)
    `catchAll` \_ -> return ()

-------------------------------------------------

runTest :: (Config -> IO a) -> IO a
runTest f = do
  pool <- newServerPool localServer []
  HC.withManager settings (f . Config rootCreds pool)
  where
    settings = HC.defaultManagerSettings

newName :: IO Text
newName = do
  uniq <- newUnique
  return $ T.pack $ "test_" ++ show (hashUnique uniq)

withTestDatabase :: Config -> (Text -> IO a) -> IO a
withTestDatabase config = bracket acquire release
  where
    acquire = do
      name <- newName
      dropDatabaseIfExists config name
      createDatabase config name
      return name
    release = dropDatabase config

catchAll :: IO a -> (SomeException -> IO a) -> IO a
catchAll = E.catch

assertStatusCodeException :: Show a => IO a -> IO ()
assertStatusCodeException io = do
  r <- try io
  case r of
    Left e -> case fromException e of
      Just HC.StatusCodeException {} -> return ()
      _ ->
        assertFailure $ "Expect a StatusCodeException, but got " ++ show e
    Right ss -> assertFailure $ "Expect an exception, but got " ++ show ss

-------------------------------------------------

main :: IO ()
main = $defaultMainGenerator

-------------------------------------------------
-- Instance deriving

deriveSeriesData defaultOptions
  { fieldLabelModifier = stripPrefixLower "wholeFloat" }
  ''WholeFloat
