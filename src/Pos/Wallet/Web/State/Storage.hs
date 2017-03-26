{-# LANGUAGE Rank2Types      #-}
{-# LANGUAGE TemplateHaskell #-}

-- @jens: this document is inspired by https://github.com/input-output-hk/rscoin-haskell/blob/master/src/RSCoin/Explorer/Storage.hs
module Pos.Wallet.Web.State.Storage
       (
         WalletStorage (..)
       , Query
       , Update
       , getProfile
       , setProfile
       , getWalletAddresses
       , getWalletMetas
       , getWalletMeta
       , getWSetMetas
       , getWSetMeta
       , getWalletAccounts
       , getAddressPath
       , getTxMeta
       , getUpdates
       , getNextUpdate
       , getHistoryCache
       , createWallet
       , createWSet
       , addWalletAccount
       , addAddressPath
       , setWalletMeta
       , setWSetMeta
       , setWalletHistory
       , getWalletHistory
       , addOnlyNewTxMeta
       , setWalletTransactionMeta
       , removeWallet
       , removeWalletAccount
       , addUpdate
       , removeNextUpdate
       , testReset
       , updateHistoryCache
       ) where

import           Universum

import           Control.Lens               (at, ix, makeClassy, (%=), (.=), (?=), _Just,
                                             _head)
import           Control.Monad.State.Class  (put)
import           Data.Default               (Default, def)
import qualified Data.HashMap.Strict        as HM
import           Data.SafeCopy              (base, deriveSafeCopySimple)
import           Pos.Client.Txp.History     (TxHistoryEntry)
import           Pos.Txp                    (Utxo)
import           Pos.Types                  (HeaderHash)
import           Pos.Wallet.Web.ClientTypes (CAddress, CCurrency, CHash, CProfile, CTxId,
                                             CTxMeta, CUpdateInfo, CWalletMeta,
                                             CWalletSetMeta, CWalletType)

type TransactionHistory = HashMap CTxId CTxMeta

type Accounts = HashSet CAddress

data WalletStorage = WalletStorage
    { _wsWSetMetas    :: !(HashMap CAddress CWalletSetMeta)
    , _wsWalletMetas  :: !(HashMap CAddress (CWalletMeta, TransactionHistory, Accounts))
    , _wsAddressPaths :: !(HashMap CAddress [Word32])
    , _wsProfile      :: !(Maybe CProfile)
    , _wsReadyUpdates :: [CUpdateInfo]
    , _wsHistoryCache :: !(HashMap CAddress (HeaderHash, Utxo, [TxHistoryEntry]))
    }

makeClassy ''WalletStorage

instance Default WalletStorage where
    def =
        WalletStorage
        { _wsWSetMetas = mempty
        , _wsWalletMetas = mempty
        , _wsAddressPaths = mempty
        , _wsProfile = mzero
        , _wsReadyUpdates = mempty
        , _wsHistoryCache = mempty
        }

type Query a = forall m. (MonadReader WalletStorage m) => m a
type Update a = forall m. ({-MonadThrow m, -}MonadState WalletStorage m) => m a

getProfile :: Query (Maybe CProfile)
getProfile = view wsProfile

setProfile :: CProfile -> Update ()
setProfile profile = wsProfile ?= profile

getWalletAddresses :: Query [CAddress]
getWalletAddresses = HM.keys <$> view wsWalletMetas

getWalletMetas :: Query [CWalletMeta]
getWalletMetas = toList . map (view _1) <$> view wsWalletMetas

getWalletMeta :: CAddress -> Query (Maybe CWalletMeta)
getWalletMeta cAddr = preview (wsWalletMetas . ix cAddr . _1)

getWSetMetas :: Query [CWalletSetMeta]
getWSetMetas = toList <$> view wsWSetMetas

getWSetMeta :: CAddress -> Query (Maybe CWalletSetMeta)
getWSetMeta cAddr = preview (wsWSetMetas . ix cAddr)

getWalletAccounts :: CAddress -> Query (Maybe [CAddress])
getWalletAccounts walletAddr = toList <<$>> preview (wsWalletMetas . ix walletAddr . _3)

getAddressPath :: CAddress -> Query (Maybe [Word32])
getAddressPath cAddr = preview (wsAddressPaths . ix cAddr)

getTxMeta :: CAddress -> CTxId -> Query (Maybe CTxMeta)
getTxMeta cAddr ctxId = preview $ wsWalletMetas . at cAddr . _Just . _2 . at ctxId . _Just

getWalletHistory :: CAddress -> Query (Maybe [CTxMeta])
getWalletHistory cAddr = fmap toList <$> preview (wsWalletMetas . ix cAddr . _2)

getUpdates :: Query [CUpdateInfo]
getUpdates = view wsReadyUpdates

getNextUpdate :: Query (Maybe CUpdateInfo)
getNextUpdate = preview (wsReadyUpdates . _head)

getHistoryCache :: CAddress -> Query (Maybe (HeaderHash, Utxo, [TxHistoryEntry]))
getHistoryCache cAddr = view $ wsHistoryCache . at cAddr

createWallet :: CAddress -> CWalletMeta -> Update ()
createWallet cAddr wMeta = wsWalletMetas . at cAddr ?= (wMeta, mempty, mempty)

createWSet :: CAddress -> CWalletSetMeta -> Update ()
createWSet cAddr wSMeta = wsWSetMetas . at cAddr ?= wSMeta

addWalletAccount :: CAddress -> CAddress -> Update ()
addWalletAccount walletAddr accountAddr = wsWalletMetas . at walletAddr . _Just . _3 . at accountAddr ?= ()

addAddressPath :: CAddress -> [Word32] -> Update ()
addAddressPath cAddr path = wsAddressPaths . at cAddr ?= path

setWalletMeta :: CAddress -> CWalletMeta -> Update ()
setWalletMeta cAddr wMeta = wsWalletMetas . at cAddr . _Just . _1 .= wMeta

setWSetMeta :: CAddress -> CWalletSetMeta -> Update ()
setWSetMeta cAddr wSMeta = wsWSetMetas . at cAddr ?= wSMeta

addWalletHistoryTx :: CAddress -> CTxId -> CTxMeta -> Update ()
addWalletHistoryTx cAddr ctxId ctxMeta = wsWalletMetas . at cAddr . _Just . _2 . at ctxId ?= ctxMeta

setWalletHistory :: CAddress -> [(CTxId, CTxMeta)] -> Update ()
setWalletHistory cAddr ctxs = () <$ mapM (uncurry $ addWalletHistoryTx cAddr) ctxs

-- FIXME: this will be removed later (temporary solution)
addOnlyNewTxMeta :: CAddress -> CTxId -> CTxMeta -> Update ()
addOnlyNewTxMeta cAddr ctxId ctxMeta = wsWalletMetas . at cAddr . _Just . _2 . at ctxId %= Just . maybe ctxMeta identity

-- NOTE: sets transaction meta only for transactions ids that are already seen
setWalletTransactionMeta :: CAddress -> CTxId -> CTxMeta -> Update ()
setWalletTransactionMeta cAddr ctxId ctxMeta = wsWalletMetas . at cAddr . _Just . _2 . at ctxId %= fmap (const ctxMeta)

removeWallet :: CAddress -> Update ()
removeWallet cAddr = wsWalletMetas . at cAddr .= Nothing

removeWalletAccount :: CAddress -> CAddress -> Update ()
removeWalletAccount walletAddr accountAddr = wsWalletMetas . at walletAddr . _Just . _3 . at accountAddr .= Nothing

addUpdate :: CUpdateInfo -> Update ()
addUpdate ui = wsReadyUpdates %= (++ [ui])

removeNextUpdate :: Update ()
removeNextUpdate = wsReadyUpdates %= drop 1

testReset :: Update ()
testReset = put def

updateHistoryCache :: CAddress -> HeaderHash -> Utxo -> [TxHistoryEntry] -> Update ()
updateHistoryCache cAddr cHash utxo cTxs = wsHistoryCache . at cAddr ?= (cHash, utxo, cTxs)

deriveSafeCopySimple 0 'base ''CProfile
deriveSafeCopySimple 0 'base ''CHash
deriveSafeCopySimple 0 'base ''CAddress
deriveSafeCopySimple 0 'base ''CCurrency
deriveSafeCopySimple 0 'base ''CWalletType
deriveSafeCopySimple 0 'base ''CWalletMeta
deriveSafeCopySimple 0 'base ''CWalletSetMeta
deriveSafeCopySimple 0 'base ''CTxId
deriveSafeCopySimple 0 'base ''TxHistoryEntry
deriveSafeCopySimple 0 'base ''CTxMeta
deriveSafeCopySimple 0 'base ''CUpdateInfo
deriveSafeCopySimple 0 'base ''WalletStorage
