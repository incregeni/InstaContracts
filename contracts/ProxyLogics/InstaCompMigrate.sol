pragma solidity ^0.5.7;
/**
 compound debt migrate
 */
interface CTokenInterface {
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function borrowBalanceCurrent(address account) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function totalReserves() external view returns (uint);
    function underlying() external view returns (address);

    function balanceOf(address owner) external view returns (uint256 balance);
    function allowance(address, address) external view returns (uint);
    function approve(address, uint) external;
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
}

interface ERC20Interface {
    function allowance(address, address) external view returns (uint);
    function balanceOf(address) external view returns (uint);
    function approve(address, uint) external;
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
}

interface ComptrollerInterface {
    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);
    function exitMarket(address cTokenAddress) external returns (uint);
    function getAssetsIn(address account) external view returns (address[] memory);
    function getAccountLiquidity(address account) external view returns (uint, uint, uint);
}

interface PoolInterface {
    function accessToken(address[] calldata ctknAddr, uint[] calldata tknAmt, bool isCompound) external;
    function paybackToken(address[] calldata ctknAddr, bool isCompound) external payable;
}

/** Swap Functionality */
interface ScdMcdMigration {
    function swapDaiToSai(uint daiAmt) external;
    function swapSaiToDai(uint saiAmt) external;
}

interface InstaMcdAddress {
    function manager() external returns (address);
    function dai() external returns (address);
    function daiJoin() external returns (address);
    function vat() external returns (address);
    function jug() external returns (address);
    function cat() external returns (address);
    function gov() external returns (address);
    function adm() external returns (address);
    function vow() external returns (address);
    function spot() external returns (address);
    function pot() external returns (address);
    function esm() external returns (address);
    function mcdFlap() external returns (address);
    function mcdFlop() external returns (address);
    function mcdDeploy() external returns (address);
    function mcdEnd() external returns (address);
    function proxyActions() external returns (address);
    function proxyActionsEnd() external returns (address);
    function proxyActionsDsr() external returns (address);
    function getCdps() external returns (address);
    function saiTub() external returns (address);
    function weth() external returns (address);
    function bat() external returns (address);
    function sai() external returns (address);
    function ethAJoin() external returns (address);
    function ethAFlip() external returns (address);
    function batAJoin() external returns (address);
    function batAFlip() external returns (address);
    function ethPip() external returns (address);
    function batAPip() external returns (address);
    function saiJoin() external returns (address);
    function saiFlip() external returns (address);
    function saiPip() external returns (address);
    function migration() external returns (address payable);
}


contract DSMath {

    function sub(uint x, uint y) internal pure returns (uint z) {
        z = x - y <= x ? x - y : 0;
    }

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "math-not-safe");
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "math-not-safe");
    }

    uint constant WAD = 10 ** 18;

    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }

    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }

}


contract Helpers is DSMath {

    /**
     * @dev get Compound Comptroller Address
     */
    function getComptrollerAddress() public pure returns (address troller) {
        troller = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    }

    /**
     * @dev get MakerDAO MCD Address contract
     */
    function getMcdAddresses() public pure returns (address mcd) {
        mcd = 0x448a5065aeBB8E423F0896E6c5D525C040f59af3; // Check Thrilok - add addr at time of deploy
    }

    /**
     * @dev get Compound Comptroller Address
     */
    function getCSaiAddress() public pure returns (address csaiAddr) {
        csaiAddr = 0xF5DCe57282A584D2746FaF1593d3121Fcac444dC;
    }

    /**
     * @dev get Compound Comptroller Address
     */
    function getCDaiAddress() public pure returns (address cdaiAddr) {
        cdaiAddr = 0xF5DCe57282A584D2746FaF1593d3121Fcac444dC; //Check Thrilok - add address before release
    }

    /**
     * @dev get Compound Comptroller Address
     */
    function getSaiAddress() public pure returns (address saiAddr) {
        saiAddr = 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359;
    }

    /**
     * @dev get Compound Comptroller Address
     */
    function getDaiAddress() public pure returns (address daiAddr) {
        daiAddr = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    }

    /**
     * @dev get Compound Comptroller Address
     */
    function getLiquidityAddress() public pure returns (address poolAddr) {
        poolAddr = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    }

    function enterMarket(address cErc20) internal {
        ComptrollerInterface troller = ComptrollerInterface(getComptrollerAddress());
        address[] memory markets = troller.getAssetsIn(address(this));
        bool isEntered = false;
        for (uint i = 0; i < markets.length; i++) {
            if (markets[i] == cErc20) {
                isEntered = true;
            }
        }
        if (!isEntered) {
            address[] memory toEnter = new address[](1);
            toEnter[0] = cErc20;
            troller.enterMarkets(toEnter);
        }
    }

    /**
     * @dev setting allowance to compound for the "user proxy" if required
     */
    function setApproval(address erc20, uint srcAmt, address to) internal {
        ERC20Interface erc20Contract = ERC20Interface(erc20);
        uint tokenAllowance = erc20Contract.allowance(address(this), to);
        if (srcAmt > tokenAllowance) {
            erc20Contract.approve(to, uint(-1));
        }
    }

}


contract PoolActions is Helpers {

    function accessLiquidity(uint amt) internal {
        address[] memory ctknAddrArr = new address[](1);
        ctknAddrArr[0] = getCSaiAddress();
        uint[] memory tknAmtArr = new uint[](1);
        tknAmtArr[0] = amt;
        PoolInterface(getLiquidityAddress()).accessToken(ctknAddrArr, tknAmtArr, false);
    }

    function paybackLiquidity(uint amt) internal {
        address[] memory ctknAddrArr = new address[](1);
        ctknAddrArr[0] = getCSaiAddress();
        ERC20Interface(getDaiAddress()).transfer(getLiquidityAddress(), amt);
        PoolInterface(getLiquidityAddress()).paybackToken(ctknAddrArr, false);
    }

}


/** Swap from Dai to Sai */
contract MigrationProxyActions is PoolActions {

    function swapSaiToDai(
        uint wad                            // Amount to swap
    ) internal
    {
        address payable scdMcdMigration = InstaMcdAddress(getMcdAddresses()).migration();
        ERC20Interface sai = ERC20Interface(getSaiAddress());
        if (sai.allowance(address(this), scdMcdMigration) < wad) {
            sai.approve(scdMcdMigration, wad);
        }
        ScdMcdMigration(scdMcdMigration).swapSaiToDai(wad);
    }

    function swapDaiToSai(
        uint wad                            // Amount to swap
    ) internal
    {
        address payable scdMcdMigration = InstaMcdAddress(getMcdAddresses()).migration();
        ERC20Interface sai = ERC20Interface(getSaiAddress());
        ERC20Interface dai = ERC20Interface(getDaiAddress());
        if (dai.allowance(address(this), scdMcdMigration) < wad) {
            dai.approve(scdMcdMigration, wad);
        }
        ScdMcdMigration(scdMcdMigration).swapDaiToSai(wad);
        sai.transfer(getLiquidityAddress(), wad);
        paybackLiquidity(wad);
    }

}


contract CompoundResolver is MigrationProxyActions {

    /**
     * @dev Redeem ETH/ERC20 and burn Compound Tokens
     * @param cTokenAmt Amount of CToken To burn
     */
    function redeemCSai(address cErc20, uint cTokenAmt) internal {
        CTokenInterface cToken = CTokenInterface(cErc20);
        uint toRedeem = cToken.balanceOf(address(this));
        toRedeem = toRedeem > cTokenAmt ? cTokenAmt : toRedeem;
        require(cToken.redeem(toRedeem) == 0, "something went wrong");
    }

    /**
     * @dev Deposit ETH/ERC20 and mint Compound Tokens
     */
    function mintCDai(address cErc20) internal {
        enterMarket(cErc20);
        CTokenInterface cToken = CTokenInterface(cErc20);
        address erc20 = cToken.underlying();
        uint toDeposit = ERC20Interface(erc20).balanceOf(address(this));
        setApproval(erc20, toDeposit, cErc20);
        assert(cToken.mint(toDeposit) == 0);
    }

    /**
     * @dev borrow ETH/ERC20
     */
    function borrowDAI(uint tokenAmt) internal {
        enterMarket(getCDaiAddress());
        require(CTokenInterface(getCDaiAddress()).borrow(tokenAmt) == 0, "got collateral?");
    }

    /**
     * @dev Pay Debt ETH/ERC20
     */
    function repaySAI(uint tokenAmt) internal returns (uint toRepay) {
        CTokenInterface cToken = CTokenInterface(getCSaiAddress());
        toRepay = cToken.borrowBalanceCurrent(address(this));
        toRepay = toRepay > tokenAmt ? tokenAmt : toRepay;
        accessLiquidity(toRepay);
        setApproval(cToken.underlying(), toRepay, getCSaiAddress());
        require(cToken.repayBorrow(toRepay) == 0, "Enough Tokens?");
    }
}


contract CompMigration is CompoundResolver {

    event LogCompMigrateCSaiToCDai(uint swapAmt, address owner);
    event LogCompMigrateDebt(uint migrateAmt, address owner);

    function migrateCSaiToCDai(uint ctknToMigrate) external {
        redeemCSai(getCSaiAddress(), ctknToMigrate);
        uint saiBal = ERC20Interface(getSaiAddress()).balanceOf(address(this));
        swapSaiToDai(saiBal);
        mintCDai(getCDaiAddress());
        emit LogCompMigrateCSaiToCDai(saiBal, address(this));
    }

    function migrateDebt(uint debtToMigrate) external {
        uint initialPoolBal = sub(getLiquidityAddress().balance, 10000000000);

        uint saiJoinBal = ERC20Interface(getSaiAddress()).balanceOf(InstaMcdAddress(getMcdAddresses()).saiJoin());
        // Check SAI balance of migration contract. If less than debtToMigrate then set debtToMigrate = SAI_Bal
        uint migrateAmt = debtToMigrate < saiJoinBal ? debtToMigrate : sub(saiJoinBal, 1000);

        uint debtPaid = repaySAI(migrateAmt); // Repaying SAI debt using InstaDApp pool
        borrowDAI(debtPaid); // borrowing DAI debt
        swapDaiToSai(debtPaid); // swapping SAI into DAI and paying back to InstaDApp pool
        uint finalPoolBal = getLiquidityAddress().balance;
        assert(finalPoolBal >= initialPoolBal);
        emit LogCompMigrateDebt(debtPaid, address(this));
    }

}


contract InstaCompoundMigrate is CompMigration {

    function() external payable {}

}