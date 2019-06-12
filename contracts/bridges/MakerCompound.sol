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

    address public daiAdd = 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359;
    // address public daiAdd = 0x5592EC0cfb4dbc12D3aB100b257153436a1f0FEa; // Rinkeby
    address public cDaiAdd = 0xF5DCe57282A584D2746FaF1593d3121Fcac444dC;
    // address public cDaiAdd = 0x6D7F0754FFeb405d23C51CE938289d4835bE3b14; // Rinkeby
    address public registryAdd = 0xF5DCe57282A584D2746FaF1593d3121Fcac444dC;
    mapping (address => uint) public deposited; // Amount of CToken deposited
    mapping (address => bool) public isAdmin;

    /**
     * @dev setting allowance to compound for the "user proxy" if required
     */
    function setApproval(address erc20, uint srcAmt, address to) public {
        require(isAdmin[msg.sender] == true, "Not-Admin");
        ERC20Interface erc20Contract = ERC20Interface(erc20);
        uint tokenAllowance = erc20Contract.allowance(address(this), to);
        if (srcAmt > tokenAllowance) {
            erc20Contract.approve(to, 2**255);
        }
    }

}


contract Bridge is Helper {

    function depositDAI(uint amt) public {
        ERC20Interface(daiAdd).transferFrom(msg.sender, address(this), amt);
        CTokenInterface cToken = CTokenInterface(cDaiAdd);
        assert(cToken.mint(amt) == 0);
        uint cDaiAmt = wdiv(amt, cToken.exchangeRateCurrent());
        deposited[msg.sender] += cDaiAmt;
    }

    function withdrawDAI(uint amt) public {
        require(deposited[msg.sender] != 0, "Nothing to Withdraw");
        CTokenInterface cToken = CTokenInterface(cDaiAdd);
        uint withdrawAmt = wdiv(amt, cToken.exchangeRateCurrent());
        uint daiAmt = amt;
        if (withdrawAmt > deposited[msg.sender]) {
            withdrawAmt = deposited[msg.sender];
            daiAmt = wmul(withdrawAmt, cToken.exchangeRateCurrent());
        }
        require(cToken.redeem(withdrawAmt) == 0, "something went wrong");
        ERC20Interface(daiAdd).transfer(msg.sender, daiAmt);
        deposited[msg.sender] -= withdrawAmt;
    }

    function depositCDAI(uint amt) public {
        CTokenInterface cToken = CTokenInterface(cDaiAdd);
        require(cToken.transferFrom(msg.sender, address(this), amt) == true, "Nothing to deposit");
        deposited[msg.sender] += amt;
    }

    function withdrawCDAI(uint amt) public {
        require(deposited[msg.sender] != 0, "Nothing to Withdraw");
        CTokenInterface cToken = CTokenInterface(cDaiAdd);
        uint withdrawAmt = amt;
        if (withdrawAmt > deposited[msg.sender]) {
            withdrawAmt = deposited[msg.sender];
        }
        cToken.transfer(msg.sender, withdrawAmt);
        deposited[msg.sender] -= withdrawAmt;
    }

    function transferDAI(uint amt) public {
        require(RegistryInterface(registryAdd).proxies(msg.sender) != address(0), "Not-User-Wallet");
        CTokenInterface cToken = CTokenInterface(cDaiAdd);
        require(cToken.redeemUnderlying(amt) == 0, "something went wrong");
        ERC20Interface(daiAdd).transfer(msg.sender, amt);
    }

    function transferBackDAI(uint amt) public {
        require(RegistryInterface(registryAdd).proxies(msg.sender) != address(0), "Not-User-Wallet");
        ERC20Interface tokenContract = ERC20Interface(daiAdd);
        tokenContract.transferFrom(msg.sender, address(this), amt);
        CTokenInterface cToken = CTokenInterface(cDaiAdd);
        assert(cToken.mint(amt) == 0);
    }

}


contract MakerCompBridge is Bridge {

    uint public version;

    /**
     * @dev setting up variables on deployment
     * 1...2...3 versioning in each subsequent deployments
     */
    constructor(uint _version) public {
        isAdmin[0x7284a8451d9a0e7Dc62B3a71C0593eA2eC5c5638] = true;
        isAdmin[0xa7615CD307F323172331865181DC8b80a2834324] = true;
        version = _version;
    }

    function() external payable {}

}