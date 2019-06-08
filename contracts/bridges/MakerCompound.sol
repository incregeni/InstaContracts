pragma solidity ^0.5.7;

interface RegistryInterface {
    function proxies(address) external view returns (address);
}

interface CTokenInterface {
    function mint(uint mintAmount) external returns (uint); // For ERC20
    function repayBorrow(uint repayAmount) external returns (uint); // For ERC20
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint); // For ERC20
    function borrowBalanceCurrent(address account) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function liquidateBorrow(address borrower, uint repayAmount, address cTokenCollateral) external returns (uint);
    function liquidateBorrow(address borrower, address cTokenCollateral) external payable;
    function exchangeRateCurrent() external returns (uint);
    function getCash() external view returns (uint);
    function totalBorrowsCurrent() external returns (uint);
    function borrowRatePerBlock() external view returns (uint);
    function supplyRatePerBlock() external view returns (uint);
    function totalReserves() external view returns (uint);
    function reserveFactorMantissa() external view returns (uint);

    function totalSupply() external view returns (uint256);
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


contract Helper is DSMath {

    address public admin = 0x7284a8451d9a0e7Dc62B3a71C0593eA2eC5c5638;
    address public dai = 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359;
    address public cDai = 0xF5DCe57282A584D2746FaF1593d3121Fcac444dC;
    mapping (address => uint) deposited; // Amount of CToken deposited

    /**
     * @dev setting allowance to compound for the "user proxy" if required
     */
    function setApproval(address erc20, uint srcAmt, address to) internal {
        ERC20Interface erc20Contract = ERC20Interface(erc20);
        uint tokenAllowance = erc20Contract.allowance(address(this), to);
        if (srcAmt > tokenAllowance) {
            erc20Contract.approve(to, 2**255);
        }
    }

}


contract Bridge is Helper {

    function depositDAI(uint amt) public {
        ERC20Interface tokenContract = ERC20Interface(dai);
        uint toDeposit = tokenContract.balanceOf(msg.sender);
        if (toDeposit > amt) {
            toDeposit = amt;
        }
        tokenContract.transferFrom(msg.sender, address(this), toDeposit);
        CTokenInterface cToken = CTokenInterface(cDai);
        setApproval(dai, toDeposit, cDai);
        assert(cToken.mint(toDeposit) == 0);
        uint cTokenMinted = wdiv(toDeposit, cToken.exchangeRateCurrent());
        deposited[msg.sender] += cTokenMinted;
    }

    function withdrawDAI(uint amt) public {

    }

}