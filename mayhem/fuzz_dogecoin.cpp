// libFuzzer port of upstream's src/test/test_bitcoin_fuzzy.cpp: the first 4 bytes pick which
// consensus/network object to deserialize, the rest is the serialized payload.
#if defined(HAVE_CONFIG_H)
#include "config/bitcoin-config.h"
#endif

#include "consensus/merkle.h"
#include "primitives/block.h"
#include "script/script.h"
#include "addrman.h"
#include "bloom.h"
#include "chain.h"
#include "coins.h"
#include "compressor.h"
#include "net.h"
#include "protocol.h"
#include "streams.h"
#include "undo.h"
#include "version.h"
#include "pubkey.h"

#include <stdint.h>
#include <string.h>

#include <vector>

enum TEST_ID {
    CBLOCK_DESERIALIZE = 0,
    CTRANSACTION_DESERIALIZE,
    CBLOCKLOCATOR_DESERIALIZE,
    CBLOCKMERKLEROOT,
    CADDRMAN_DESERIALIZE,
    CBLOCKHEADER_DESERIALIZE,
    CBANENTRY_DESERIALIZE,
    CTXUNDO_DESERIALIZE,
    CBLOCKUNDO_DESERIALIZE,
    CCOINS_DESERIALIZE,
    CNETADDR_DESERIALIZE,
    CSERVICE_DESERIALIZE,
    CMESSAGEHEADER_DESERIALIZE,
    CADDRESS_DESERIALIZE,
    CINV_DESERIALIZE,
    CBLOOMFILTER_DESERIALIZE,
    CDISKBLOCKINDEX_DESERIALIZE,
    CTXOUTCOMPRESSOR_DESERIALIZE,
    TEST_ID_END
};

static ECCVerifyHandle globalVerifyHandle;

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < sizeof(uint32_t)) return -1;
    if (size > (1 << 20)) return -1;

    uint32_t test_id = 0xffffffff;
    memcpy(&test_id, data, sizeof(uint32_t));
    if (test_id >= TEST_ID_END) return -1;

    std::vector<char> buffer((const char *)data + sizeof(uint32_t), (const char *)data + size);
    CDataStream ds(buffer, SER_NETWORK, INIT_PROTO_VERSION);
    try {
        int nVersion;
        ds >> nVersion;
        ds.SetVersion(nVersion);
    } catch (const std::ios_base::failure &e) {
        return 0;
    }

    try {
        switch (test_id) {
        case CBLOCK_DESERIALIZE: {
            CBlock block;
            ds >> block;
            break;
        }
        case CTRANSACTION_DESERIALIZE: {
            CTransaction tx(deserialize, ds);
            break;
        }
        case CBLOCKLOCATOR_DESERIALIZE: {
            CBlockLocator bl;
            ds >> bl;
            break;
        }
        case CBLOCKMERKLEROOT: {
            CBlock block;
            ds >> block;
            bool mutated;
            BlockMerkleRoot(block, &mutated);
            break;
        }
        case CADDRMAN_DESERIALIZE: {
            CAddrMan am;
            ds >> am;
            break;
        }
        case CBLOCKHEADER_DESERIALIZE: {
            CBlockHeader bh;
            ds >> bh;
            break;
        }
        case CBANENTRY_DESERIALIZE: {
            CBanEntry be;
            ds >> be;
            break;
        }
        case CTXUNDO_DESERIALIZE: {
            CTxUndo tu;
            ds >> tu;
            break;
        }
        case CBLOCKUNDO_DESERIALIZE: {
            CBlockUndo bu;
            ds >> bu;
            break;
        }
        case CCOINS_DESERIALIZE: {
            CCoins coins;
            ds >> coins;
            break;
        }
        case CNETADDR_DESERIALIZE: {
            CNetAddr na;
            ds >> na;
            break;
        }
        case CSERVICE_DESERIALIZE: {
            CService s;
            ds >> s;
            break;
        }
        case CMESSAGEHEADER_DESERIALIZE: {
            CMessageHeader::MessageStartChars pchMessageStart = {0x00, 0x00, 0x00, 0x00};
            CMessageHeader mh(pchMessageStart);
            ds >> mh;
            if (!mh.IsValid(pchMessageStart)) return 0;
            break;
        }
        case CADDRESS_DESERIALIZE: {
            CAddress a;
            ds >> a;
            break;
        }
        case CINV_DESERIALIZE: {
            CInv i;
            ds >> i;
            break;
        }
        case CBLOOMFILTER_DESERIALIZE: {
            CBloomFilter bf;
            ds >> bf;
            break;
        }
        case CDISKBLOCKINDEX_DESERIALIZE: {
            CDiskBlockIndex dbi;
            ds >> dbi;
            break;
        }
        case CTXOUTCOMPRESSOR_DESERIALIZE: {
            CTxOut to;
            CTxOutCompressor toc(to);
            ds >> toc;
            break;
        }
        default:
            return -1;
        }
    } catch (const std::ios_base::failure &e) {
        return 0;
    }
    return 0;
}
