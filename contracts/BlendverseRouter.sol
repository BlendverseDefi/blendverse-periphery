pragma solidity =0.6.6;

import '../../blendverse-core/contracts/interfaces/IBlendverseFactory.sol';
import '../../blendverse-lib/contracts/utils/TransferHelper.sol';

import './interfaces/IBlendverseRouter.sol';
import './libraries/BlendverseLibrary.sol';
import '../../blendverse-lib/contracts/math/SafeMath.sol';
import '../../blendverse-lib/contracts/token/BEP20/IBEP20.sol';
import './interfaces/IWMATIC.sol';

contract BlendverseRouter is IBlendverseRouter {
    using SafeMath for uint256;
    address public immutable override factory;
    address public immutable override WMATIC;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'BlendverseRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WMATIC) public {
        factory = _factory;
        WMATIC = _WMATIC;
    }

    receive() external payable {
        assert(msg.sender == WMATIC); // only accept MATIC via fallback from the WMATIC contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IBlendverseFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IBlendverseFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = BlendverseLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = BlendverseLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'BlendverseRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = BlendverseLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'BlendverseRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = BlendverseLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IBlendversePair(pair).mint(to);
    }

    function addLiquidityMATIC(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountMATICMin,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (
            uint256 amountToken,
            uint256 amountMATIC,
            uint256 liquidity
        )
    {
        (amountToken, amountMATIC) = _addLiquidity(
            token,
            WMATIC,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountMATICMin
        );
        address pair = BlendverseLibrary.pairFor(factory, token, WMATIC);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWMATIC(WMATIC).deposit{value: amountMATIC}();
        assert(IWMATIC(WMATIC).transfer(pair, amountMATIC));
        liquidity = IBlendversePair(pair).mint(to);
        // refund dust MATIC, if any
        if (msg.value > amountMATIC) TransferHelper.safeTransferMATIC(msg.sender, msg.value - amountMATIC);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = BlendverseLibrary.pairFor(factory, tokenA, tokenB);
        IBlendversePair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IBlendversePair(pair).burn(to);
        (address token0, ) = BlendverseLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'BlendverseRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'BlendverseRouter: INSUFFICIENT_B_AMOUNT');
    }

    function removeLiquidityMATIC(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountMATICMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountMATIC) {
        (amountToken, amountMATIC) = removeLiquidity(
            token,
            WMATIC,
            liquidity,
            amountTokenMin,
            amountMATICMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWMATIC(WMATIC).withdraw(amountMATIC);
        TransferHelper.safeTransferMATIC(to, amountMATIC);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        address pair = BlendverseLibrary.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IBlendversePair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityMATICWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountMATICMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountToken, uint256 amountMATIC) {
        address pair = BlendverseLibrary.pairFor(factory, token, WMATIC);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IBlendversePair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountMATIC) = removeLiquidityMATIC(token, liquidity, amountTokenMin, amountMATICMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityMATICSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountMATICMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountMATIC) {
        (, amountMATIC) = removeLiquidity(token, WMATIC, liquidity, amountTokenMin, amountMATICMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, IBEP20(token).balanceOf(address(this)));
        IWMATIC(WMATIC).withdraw(amountMATIC);
        TransferHelper.safeTransferMATIC(to, amountMATIC);
    }

    function removeLiquidityMATICWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountMATICMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountMATIC) {
        address pair = BlendverseLibrary.pairFor(factory, token, WMATIC);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IBlendversePair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountMATIC = removeLiquidityMATICSupportingFeeOnTransferTokens(
            token,
            liquidity,
            amountTokenMin,
            amountMATICMin,
            to,
            deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = BlendverseLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2 ? BlendverseLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IBlendversePair(BlendverseLibrary.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to);
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = BlendverseLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'BlendverseRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            BlendverseLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = BlendverseLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'BlendverseRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            BlendverseLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapExactMATICForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override payable ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WMATIC, 'BlendverseRouter: INVALID_PATH');
        amounts = BlendverseLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'BlendverseRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWMATIC(WMATIC).deposit{value: amounts[0]}();
        assert(IWMATIC(WMATIC).transfer(BlendverseLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    function swapTokensForExactMATIC(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WMATIC, 'BlendverseRouter: INVALID_PATH');
        amounts = BlendverseLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'BlendverseRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            BlendverseLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWMATIC(WMATIC).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferMATIC(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForMATIC(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WMATIC, 'BlendverseRouter: INVALID_PATH');
        amounts = BlendverseLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'BlendverseRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            BlendverseLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWMATIC(WMATIC).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferMATIC(to, amounts[amounts.length - 1]);
    }

    function swapMATICForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override payable ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WMATIC, 'BlendverseRouter: INVALID_PATH');
        amounts = BlendverseLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'BlendverseRouter: EXCESSIVE_INPUT_AMOUNT');
        IWMATIC(WMATIC).deposit{value: amounts[0]}();
        assert(IWMATIC(WMATIC).transfer(BlendverseLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust MATIC, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferMATIC(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = BlendverseLibrary.sortTokens(input, output);
            IBlendversePair pair = IBlendversePair(BlendverseLibrary.pairFor(factory, input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);
                amountInput = IBEP20(input).balanceOf(address(pair)).sub(reserveInput);
                amountOutput = BlendverseLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOutput)
                : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? BlendverseLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to);
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            BlendverseLibrary.pairFor(factory, path[0], path[1]),
            amountIn
        );
        uint256 balanceBefore = IBEP20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IBEP20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'BlendverseRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactMATICForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override payable ensure(deadline) {
        require(path[0] == WMATIC, 'BlendverseRouter: INVALID_PATH');
        uint256 amountIn = msg.value;
        IWMATIC(WMATIC).deposit{value: amountIn}();
        assert(IWMATIC(WMATIC).transfer(BlendverseLibrary.pairFor(factory, path[0], path[1]), amountIn));
        uint256 balanceBefore = IBEP20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IBEP20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'BlendverseRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactTokensForMATICSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        require(path[path.length - 1] == WMATIC, 'BlendverseRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            BlendverseLibrary.pairFor(factory, path[0], path[1]),
            amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IBEP20(WMATIC).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'BlendverseRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWMATIC(WMATIC).withdraw(amountOut);
        TransferHelper.safeTransferMATIC(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public virtual override pure returns (uint256 amountB) {
        return BlendverseLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public virtual override pure returns (uint256 amountOut) {
        return BlendverseLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public virtual override pure returns (uint256 amountIn) {
        return BlendverseLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        virtual
        override
        view
        returns (uint256[] memory amounts)
    {
        return BlendverseLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path)
        public
        virtual
        override
        view
        returns (uint256[] memory amounts)
    {
        return BlendverseLibrary.getAmountsIn(factory, amountOut, path);
    }
}
