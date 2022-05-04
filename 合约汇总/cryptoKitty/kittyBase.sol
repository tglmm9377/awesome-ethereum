/// @title Base contract for CryptoKitties. Holds all common structs, events and base variables.
/// @author Axiom Zen (https://www.axiomzen.co)
/// @dev See the KittyCore contract documentation to understand how the various contract facets are arranged.

// kitty 的基础合约保存了所有的结构体事件，基础变量
contract KittyBase is KittyAccessControl {
    /*** EVENTS ***/

    /// @dev The Birth event is fired whenever a new kitten comes into existence. This obviously
    ///  includes any time a cat is created through the giveBirth method, but it is also called
    ///  when a new gen0 cat is created.

    // 拥有者，kittyID, 母亲，父亲，基因组
    event Birth(address owner, uint256 kittyId, uint256 matronId, uint256 sireId, uint256 genes);

    /// @dev Transfer event as defined in current draft of ERC721. Emitted every time a kitten
    ///  ownership is assigned, including births.
    event Transfer(address from, address to, uint256 tokenId);

    /*** DATA TYPES ***/

    /// @dev The main Kitty struct. Every cat in CryptoKitties is represented by a copy
    ///  of this structure, so great care was taken to ensure that it fits neatly into
    ///  exactly two 256-bit words. Note that the order of the members in this structure
    ///  is important because of the byte-packing rules used by Ethereum.
    ///  Ref: http://solidity.readthedocs.io/en/develop/miscellaneous.html


    // 这是kitty 最主要的结构体，crYptokitties 上的每只猫都有一个这样的副本
    // 这个结构变量的顺序做了一定的优化 gas save，刚好是两个256,只需要调用两次SSTORE
    struct Kitty {
        // The Kitty's genetic code is packed into these 256-bits, the format is
        // sooper-sekret! A cat's genes never change.

        // 遗传代码不能被修改
        uint256 genes;

        // The timestamp from the block when this cat came into existence.
        // 猫存在时区块时间戳
        uint64 birthTime;

        // The minimum timestamp after which this cat can engage in breeding
        // activities again. This same timestamp is used for the pregnancy
        // timer (for matrons) as well as the siring cooldown.
        // 冷却道到期的时间，这个时间戳被用在 母亲的妊娠期，和父亲的冷却期。
        uint64 cooldownEndBlock;

        // The ID of the parents of this kitty, set to 0 for gen0 cats.
        // Note that using 32-bit unsigned integers limits us to a "mere"
        // 4 billion cats. This number might seem small until you realize
        // that Ethereum currently has a limit of about 500 million
        // transactions per year! So, this definitely won't be a problem
        // for several years (even as Ethereum learns to scale).

        // 父母的ID, 如果时0代猫他的父母ID是0.
        // 这个类型被设为uint32 最大 4294967295个猫
        uint32 matronId;
        uint32 sireId;

        // Set to the ID of the sire cat for matrons that are pregnant,
        // zero otherwise. A non-zero value here is how we know a cat
        // is pregnant. Used to retrieve the genetic material for the new
        // kitten when the birth transpires.

        // 设置配偶,用于孩子出生时候提取遗传信息
        uint32 siringWithId;

        // Set to the index in the cooldown array (see below) that represents
        // the current cooldown duration for this Kitty. This starts at zero
        // for gen0 cats, and is initialized to floor(generation/2) for others.
        // Incremented by one for each successful breeding action, regardless
        // of whether this cat is acting as matron or sire.

        // 冷却时间在冷却数组中对应的Index,每一次成功的繁殖都会增加一，不管这只猫是公还是母
        uint16 cooldownIndex;

        // The "generation number" of this cat. Cats minted by the CK contract
        // for sale are called "gen0" and have a generation number of 0. The
        // generation number of all other cats is the larger of the two generation
        // numbers of their parents, plus one.
        // (i.e. max(matron.generation, sire.generation) + 1)

        // 初代猫的代号为0，其他代的计算方式是，取父母两个generation 最大值再加上1
        uint16 generation;
    }

    /*** CONSTANTS ***/

    /// @dev A lookup table indicating the cooldown duration after any successful
    ///  breeding action, called "pregnancy time" for matrons and "siring cooldown"
    ///  for sires. Designed such that the cooldown roughly doubles each time a cat
    ///  is bred, encouraging owners not to just keep breeding the same cat over
    ///  and over again. Caps out at one week (a cat can breed an unbounded number
    ///  of times, and the maximum cooldown is always seven days).

    // 一个查询表，表明冷却时间在一次繁殖行为成功后，这段时间被称为母亲妊娠期 ,父亲被称为冷却时间。
    // 这样的设计冷却粗略的减缓了每一次一只猫被繁殖。鼓励拥有者不要总是培育一种猫，冷却时间最大值为 7 days

    uint32[14] public cooldowns = [
        uint32(1 minutes),
        uint32(2 minutes),
        uint32(5 minutes),
        uint32(10 minutes),
        uint32(30 minutes),
        uint32(1 hours),
        uint32(2 hours),
        uint32(4 hours),
        uint32(8 hours),
        uint32(16 hours),
        uint32(1 days),
        uint32(2 days),
        uint32(4 days),
        uint32(7 days)
    ];

    // An approximation of currently how many seconds are in between blocks.
    // 当前块间隔时间的近似值 15s
    uint256 public secondsPerBlock = 15;

    /*** STORAGE ***/

    /// @dev An array containing the Kitty struct for all Kitties in existence. The ID
    ///  of each cat is actually an index into this array. Note that ID 0 is a negacat,
    ///  the unKitty, the mythical beast that is the parent of all gen0 cats. A bizarre
    ///  creature that is both matron and sire... to itself! Has an invalid genetic code.
    ///  In other words, cat ID 0 is invalid... ;-)
    // ID是这个数组的索引，数组保存了所有存在的猫ID==0不是一个猫，他是所有猫的祖先。既是母的又是公的有一个无效的遗传代码
    // 换句话说 ID 0 是无效的。
    Kitty[] kitties;

    /// @dev A mapping from cat IDs to the address that owns them. All cats have
    ///  some valid owner address, even gen0 cats are created with a non-zero owner.
    // 0代猫CK合约生成他的Owner也是非0的，这个Map标识了 猫ID=> 拥有者
    mapping (uint256 => address) public kittyIndexToOwner;

    // @dev A mapping from owner address to count of tokens that address owns.
    //  Used internally inside balanceOf() to resolve ownership count.

    // 记录拥有者拥有猫的数量,  owner => amount
    mapping (address => uint256) ownershipTokenCount;

    /// @dev A mapping from KittyIDs to an address that has been approved to call
    ///  transferFrom(). Each Kitty can only have one approved address for transfer
    ///  at any time. A zero value means no approval is outstanding.

    // 每个kitty 只能授权给一个地址，零地址表示？ ， ID = > approved(address)
    mapping (uint256 => address) public kittyIndexToApproved;

    /// @dev A mapping from KittyIDs to an address that has been approved to use
    ///  this Kitty for siring via breedWith(). Each Kitty can only have one approved
    ///  address for siring at any time. A zero value means no approval is outstanding.
    // 父亲 ID = > approved ，表示被授权用于繁殖，在一个繁殖时间内只能授权给一个地址
    mapping (uint256 => address) public sireAllowedToAddress;

    /// @dev The address of the ClockAuction contract that handles sales of Kitties. This
    ///  same contract handles both peer-to-peer sales as well as the gen0 sales which are
    ///  initiated every 15 minutes.

    // 负责kitty 销售的合约地址，这个合约负责p2p销售也负责0代猫的销售
    SaleClockAuction public saleAuction;

    /// @dev The address of a custom ClockAuction subclassed contract that handles siring
    ///  auctions. Needs to be separate from saleAuction because the actions taken on success
    ///  after a sales and siring auction are quite different.

     // 合约是一个CK合约的子类，但与拍卖合约不同，认祖归宗
    SiringClockAuction public siringAuction;

    /// @dev Assigns ownership of a specific Kitty to an address.
    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        // Since the number of kittens is capped to 2^32 we can't overflow this
        ownershipTokenCount[_to]++;
        // transfer ownership
        kittyIndexToOwner[_tokenId] = _to;
        // When creating new kittens _from is 0x0, but we can't account that address.
        if (_from != address(0)) {
            ownershipTokenCount[_from]--;
            // once the kitten is transferred also clear sire allowances
            delete sireAllowedToAddress[_tokenId];
            // clear any previously approved ownership exchange
            delete kittyIndexToApproved[_tokenId];
        }
        // Emit the transfer event.
        Transfer(_from, _to, _tokenId);
    }

    /// @dev An internal method that creates a new kitty and stores it. This
    ///  method doesn't do any checking and should only be called when the
    ///  input data is known to be valid. Will generate both a Birth event
    ///  and a Transfer event.
    /// @param _matronId The kitty ID of the matron of this cat (zero for gen0)
    /// @param _sireId The kitty ID of the sire of this cat (zero for gen0)
    /// @param _generation The generation number of this cat, must be computed by caller.
    /// @param _genes The kitty's genetic code.
    /// @param _owner The inital owner of this cat, must be non-zero (except for the unKitty, ID 0)
    function _createKitty(
        uint256 _matronId,
        uint256 _sireId,
        uint256 _generation, // 
        uint256 _genes, // 遗传码。
        address _owner
    )
        internal
        returns (uint)
    {
        // These requires are not strictly necessary, our calling code should make
        // sure that these conditions are never broken. However! _createKitty() is already
        // an expensive call (for storage), and it doesn't hurt to be especially careful
        // to ensure our data structures are always valid.
        require(_matronId == uint256(uint32(_matronId)));
        require(_sireId == uint256(uint32(_sireId)));
        require(_generation == uint256(uint16(_generation)));

        // New kitty starts with the same cooldown as parent gen/2
        uint16 cooldownIndex = uint16(_generation / 2); // 新猫的开始冷却时间index是  代号/2,这个index对应了冷却数组的Index;
        if (cooldownIndex > 13) {
            cooldownIndex = 13;
        }

        Kitty memory _kitty = Kitty({
            genes: _genes, // 遗传码
            birthTime: uint64(now),
            cooldownEndBlock: 0,
            matronId: uint32(_matronId),
            sireId: uint32(_sireId),
            siringWithId: 0, // 默认为0，因为没有处于交配状态
            cooldownIndex: cooldownIndex, // 冷却时间
            generation: uint16(_generation) // 代号 
        });
        uint256 newKittenId = kitties.push(_kitty) - 1;

        // It's probably never going to happen, 4 billion cats is A LOT, but
        // let's just be 100% sure we never let this happen.

        // uint32 最大40亿+,这个操作保证新生成的猫ID没有溢出
        require(newKittenId == uint256(uint32(newKittenId)));

        // emit the birth event
        Birth(
            _owner,
            newKittenId,
            uint256(_kitty.matronId),
            uint256(_kitty.sireId),
            _kitty.genes
        );

        // This will assign ownership, and also emit the Transfer event as
        // per ERC721 draft

        // 将新猫的token发送给owner
        _transfer(0, _owner, newKittenId);

        return newKittenId;
    }

    // Any C-level can fix how many seconds per blocks are currently observed.

     // c-level is ceo,cfo,coo ，能够修复每个块当前观察到的秒数
    function setSecondsPerBlock(uint256 secs) external onlyCLevel {
        require(secs < cooldowns[0]);
        secondsPerBlock = secs;
    }
}

