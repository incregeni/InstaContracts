pragma solidity ^0.5.8;
pragma experimental ABIEncoderV2;

interface ERC20Interface {
    function allowance(address, address) external view returns (uint);
    function balanceOf(address) external view returns (uint);
    function approve(address, uint) external;
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
    function deposit() external payable;
    function withdraw(uint) external;
}


contract SoloMarginContract {

    struct Info {
        address owner;  // The address that owns the account
        uint256 number; // A nonce that allows a single address to control many accounts
    }

    enum ActionType {
        Deposit,   // supply tokens
        Withdraw,  // borrow tokens
        Transfer,  // transfer balance between accounts
        Buy,       // buy an amount of some token (externally)
        Sell,      // sell an amount of some token (externally)
        Trade,     // trade tokens against another account
        Liquidate, // liquidate an undercollateralized or expiring account
        Vaporize,  // use excess tokens to zero-out a completely negative account
        Call       // send arbitrary data to an address
    }

    enum AssetDenomination {
        Wei, // the amount is denominated in wei
        Par  // the amount is denominated in par
    }
    
    enum AssetReference {
        Delta, // the amount is given as a delta from the current value
        Target // the amount is given as an exact number to end up at
    }

    struct AssetAmount {
        bool sign; // true if positive
        AssetDenomination denomination;
        AssetReference ref;
        uint256 value;
    }

    struct ActionArgs {
        ActionType actionType;
        uint256 accountId;
        AssetAmount amount;
        uint256 primaryMarketId;
        uint256 secondaryMarketId;
        address otherAddress;
        uint256 otherAccountId;
        bytes data;
    }

    struct Wei {
        bool sign; // true if positive
        uint256 value;
    }

    function operate(Info[] memory accounts, ActionArgs[] memory actions) public;
    function getAccountWei(
        Info memory account,
        uint256 marketId
    )
        public
        returns (Wei memory);
}


contract PayableProxySoloMarginContract {

    function operate(
        SoloMarginContract.Info[] memory accounts,
        SoloMarginContract.ActionArgs[] memory actions,
        address payable sendEthTo
    ) public payable;
}


contract DSMath {

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
     * @dev get ethereum address
     */
    function getAddressETH() public pure returns (address eth) {
        eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    }

        /**
     * @dev get WETH address
     */
    function getAddressWETH() public pure returns (address weth) {
        weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }

    /**
     * @dev get Dydx Solo Address
     */
    function getSoloAddress() public pure returns (address addr) {
        addr = 0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e;
    }

    /**
     * @dev get Dydx Solo payable Address
     */
    function getSoloPayableAddress() public pure returns (address addr) {
        addr = 0xa8b39829cE2246f89B31C013b8Cde15506Fb9A76;
    }

    /**
     * @dev Transfer ETH/ERC20 to user
     */
    function transferToken(address erc20) internal {
        if (erc20 == getAddressETH()) {
            msg.sender.transfer(address(this).balance);
        } else {
            ERC20Interface erc20Contract = ERC20Interface(erc20);
            uint srcBal = erc20Contract.balanceOf(address(this));
            if (srcBal > 0) {
                erc20Contract.transfer(msg.sender, srcBal);
            }
        }
    }

    /**
     * @dev setting allowance to dydx for the "user proxy" if required
     */
    function setApproval(address erc20, uint srcAmt, address to) internal {
        ERC20Interface erc20Contract = ERC20Interface(erc20);
        uint tokenAllowance = erc20Contract.allowance(address(this), to);
        if (srcAmt > tokenAllowance) {
            erc20Contract.approve(to, 2**255);
        }
    }

    /**
    * @dev getting actions arg
    */
    function getActionsArgs( uint256 marketId, uint256 tokenAmt, bool sign) internal returns ( SoloMarginContract.ActionArgs[] memory) {
        SoloMarginContract.ActionArgs[] memory actions = new SoloMarginContract.ActionArgs[](1);
        SoloMarginContract.AssetAmount memory amount = SoloMarginContract.AssetAmount(
            sign,
            SoloMarginContract.AssetDenomination.Wei,
            SoloMarginContract.AssetReference.Delta,
            tokenAmt
        );
        bytes memory empty;
        address otherAddr = marketId == 0 ? getSoloPayableAddress() : address(this);
        SoloMarginContract.ActionType action = sign ? SoloMarginContract.ActionType.Deposit : SoloMarginContract.ActionType.Withdraw;
        actions[0] = SoloMarginContract.ActionArgs(
            action,
            0,
            amount,
            marketId,
            0,
            otherAddr,
            0,
            empty
        );
        return actions;
    }

     /**
     * @dev getting acccount arg
     */
    function getAccountArgs() internal returns ( SoloMarginContract.Info[] memory) {
        SoloMarginContract.Info[] memory accounts = new SoloMarginContract.Info[](1);
        accounts[0] = (SoloMarginContract.Info(address(this), 0));
        return accounts;
    }

    /**
     * @dev getting dydx balance
     */
    function getDydxBal(uint256 marketId) internal returns (uint) {
        SoloMarginContract solo = SoloMarginContract(getSoloAddress());
        SoloMarginContract.Wei memory tokenWeiBal = solo.getAccountWei(getAccountArgs()[0],marketId);
        uint tokenBal = tokenWeiBal.value;
        return tokenBal;
    }

}


contract DydxResolver is Helpers {

    event LogDeposit(address erc20Addr, uint tokenAmt, address owner);
    event LogWithdraw(address erc20Addr, uint tokenAmt, address owner);
    event LogBorrow(address erc20Addr, uint tokenAmt, address owner);
    event LogPayback(address erc20Addr, uint tokenAmt, address owner);


    /**
     * @dev Deposit ETH/ERC20
     */
    function deposit(
        uint256 marketId,
        address erc20Addr,
        uint256 tokenAmt
    ) public payable
    {

        if (erc20Addr == getAddressETH()) {
            PayableProxySoloMarginContract soloPayable = PayableProxySoloMarginContract(getSoloPayableAddress());
            soloPayable.operate.value(msg.value)(getAccountArgs(), getActionsArgs(marketId, msg.value, true), msg.sender);
        } else {
            SoloMarginContract solo = SoloMarginContract(getSoloAddress());
            ERC20Interface token = ERC20Interface(erc20Addr);

            uint toDeposit = token.balanceOf(msg.sender);
            if (toDeposit > tokenAmt) {
                toDeposit = tokenAmt;
            }

            token.transferFrom(msg.sender, address(this), toDeposit);
            setApproval(erc20Addr, 2**255, getSoloAddress());
            solo.operate(getAccountArgs(), getActionsArgs(marketId, toDeposit, true));
        }
        emit LogDeposit(erc20Addr, tokenAmt, msg.sender);
    }

    /**
     * @dev Payback ETH/ERC20
     */
    function payback(
        uint256 marketId,
        address erc20Addr,
        uint256 tokenAmt
    ) public payable
    {
        if (erc20Addr == getAddressETH()) {
            PayableProxySoloMarginContract soloPayable = PayableProxySoloMarginContract(getSoloPayableAddress());
            uint toDeposit = getDydxBal(marketId);
            if (toDeposit > tokenAmt) {
                toDeposit = tokenAmt;
            }
            soloPayable.operate.value(toDeposit)(getAccountArgs(), getActionsArgs(marketId, toDeposit, true), msg.sender);
            msg.sender.transfer(address(this).balance);
            emit LogPayback(erc20Addr, toDeposit, msg.sender);
        } else {
            SoloMarginContract solo = SoloMarginContract(getSoloAddress());
            ERC20Interface token = ERC20Interface(erc20Addr);

            uint toDeposit = getDydxBal(marketId);
            if (toDeposit > tokenAmt) {
                toDeposit = tokenAmt;
            }

            token.transferFrom(msg.sender, address(this), toDeposit);
            setApproval(erc20Addr, 2**255, getSoloAddress());
            solo.operate(getAccountArgs(), getActionsArgs(marketId, toDeposit, true));
            emit LogPayback(erc20Addr, toDeposit, msg.sender);
        }
    }

    /**
     * @dev Withdraw ETH/ERC20
     */
    function withdraw(
        uint256 marketId,
        address erc20Addr,
        uint256 tokenAmt
    ) public
    {
        if (erc20Addr == getAddressETH()) {
            PayableProxySoloMarginContract soloPayable = PayableProxySoloMarginContract(getSoloPayableAddress());
            uint toDeposit = getDydxBal(marketId);
            if (toDeposit > tokenAmt) {
                toDeposit = tokenAmt;
            }
            soloPayable.operate(getAccountArgs(), getActionsArgs(marketId, toDeposit, false), msg.sender);
            ERC20Interface weth = ERC20Interface(getAddressWETH());
            setApproval(getAddressWETH(), 2**255, getAddressWETH());
            weth.withdraw(toDeposit);
            transferToken(getAddressETH());
            emit LogWithdraw(erc20Addr, toDeposit, msg.sender);

        } else {
            SoloMarginContract solo = SoloMarginContract(getSoloAddress());
            uint toDeposit = getDydxBal(marketId);
            if (toDeposit > tokenAmt) {
                toDeposit = tokenAmt;
            }
            solo.operate(getAccountArgs(), getActionsArgs(marketId, toDeposit, false));
            setApproval(erc20Addr, 2**255, msg.sender);
            transferToken(erc20Addr);
            emit LogWithdraw(erc20Addr, toDeposit, msg.sender);
        }
    }

/**
* @dev Borrow ETH/ERC20
*/
    function borrow(
        uint256 marketId,
        address erc20Addr,
        uint256 tokenAmt
    ) public
    {
        if (erc20Addr == getAddressETH()) {
            PayableProxySoloMarginContract soloPayable = PayableProxySoloMarginContract(getSoloPayableAddress());
            soloPayable.operate(getAccountArgs(), getActionsArgs(marketId, tokenAmt, false), msg.sender);
            ERC20Interface weth = ERC20Interface(getAddressWETH());
            setApproval(getAddressWETH(), 2**255, getAddressWETH());
            weth.withdraw(tokenAmt);
            transferToken(getAddressETH());
        } else {
            SoloMarginContract solo = SoloMarginContract(getSoloAddress());
            solo.operate(getAccountArgs(), getActionsArgs(marketId, tokenAmt, false));
            setApproval(erc20Addr, 2**255, msg.sender);
            transferToken(erc20Addr);
        }
        emit LogBorrow(erc20Addr, tokenAmt, msg.sender);
    }
}


contract InstaDydx is DydxResolver {

    function() external payable {}

}
