import {Smaug} from "../Smaug.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockSafe {
    Smaug public _smaug;

    constructor(address smaug) {
        _smaug = Smaug(smaug);
    }

    function setSmaug(address smaug) public {
        _smaug = Smaug(smaug);
    }

    function imitateNumerousCalls(
        uint256 numberOfCalls,
        address assetAddress,
        uint256 amount
    ) public {
        for (uint256 i = 0; i < numberOfCalls; i++) {
            _smaug.checkTransaction(
                assetAddress,
                0,
                "0x",
                0,
                0,
                0,
                0,
                payable(msg.sender),
                payable(msg.sender),
                "0x",
                payable(msg.sender)
            );
            IERC20(assetAddress).transfer(payable(msg.sender), amount);
            _smaug.checkAfterExecution(
                keccak256(abi.encodePacked(assetAddress, amount, i)),
                true
            );
        }
    }
}
