pragma solidity =0.6.6;

import '@jishankai/uniswap-v2-core/contracts/interfaces/IERC20.sol';
import '@jishankai/uniswap-v2-core/contracts/libraries/TransferHelper.sol';
import '@jishankai/uniswap-v2-core/contracts/libraries/NativeToken.sol';

import './libraries/UniswapV2Library.sol';
import './libraries/SafeMath.sol';

contract UniswapV2Router02 is AllowNonDefaultNativeToken {
    using SafeMath for uint;

    address public immutable factory;
    mapping (uint => mapping(address => uint)) public balance;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    constructor(address _factory) public {
        factory = _factory;
    }

    receive() external payable allowToken {
        uint tokenId = NativeToken.getCurrentToken();
        balance[tokenId][msg.sender] = balance[tokenId][msg.sender].add(msg.value);
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        uint tokenA,
        uint tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        uint tokenA,
        uint tokenB,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, balance[tokenA][msg.sender], balance[tokenB][msg.sender], amountAMin, amountBMin);
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        _updateTokenBalance(tokenA, tokenB, amountA, amountB);

        TransferHelper.safeTransfer(tokenA, pair, amountA);
        TransferHelper.safeTransfer(tokenB, pair, amountB);

        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function _updateTokenBalance(
        uint tokenA,
        uint tokenB,
        uint amountA,
        uint amountB
    ) private {
        if (balance[tokenA][msg.sender] > amountA) {
            TransferHelper.safeTransfer(tokenA, msg.sender, balance[tokenA][msg.sender].sub(amountA));
        }
        if (balance[tokenB][msg.sender] > amountB) {
            TransferHelper.safeTransfer(tokenB, msg.sender, balance[tokenB][msg.sender].sub(amountB));
        }
        balance[tokenA][msg.sender] = 0;
        balance[tokenB][msg.sender] = 0;
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        uint tokenA,
        uint tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        (uint token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityWithPermit(
        uint tokenA,
        uint tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, uint[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (uint input, uint output) = (path[i], path[i + 1]);
            (uint token0,) = UniswapV2Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    function swapExactTokensForTokens(
        uint amountOutMin,
        uint[] calldata path,
        address to,
        uint deadline
    ) external payable allowToken ensure(deadline) returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransfer(
            path[0], UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint[] calldata path,
        address to,
        uint deadline
    ) external payable allowToken ensure(deadline) returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransfer(
            path[0], UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
        // refund dust native token, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransfer(path[0], msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(uint[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (uint input, uint output) = (path[i], path[i + 1]);
            (uint token0,) = UniswapV2Library.sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        uint[] calldata path,
        address to,
        uint deadline
    ) external payable allowToken ensure(deadline) {
        TransferHelper.safeTransfer(
            path[0], UniswapV2Library.pairFor(factory, path[0], path[1]), msg.value
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        returns (uint amountOut)
    {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        returns (uint amountIn)
    {
        return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, uint[] memory path)
        public
        view
        virtual
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, uint[] memory path)
        public
        view
        virtual
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }

    function getPairs()
        public
        view
        virtual
        returns (address[] memory addresses)
    {
        uint length;
        for (uint i = 0; i < IUniswapV2Factory(factory).allPairsLength(); i++) {
            address pair = IUniswapV2Factory(factory).allPairs(i);
            if(IUniswapV2Pair(pair).balanceOf(msg.sender) > 0) {
                length++;
            }
        }
        addresses = new address[](length);
        length = 0;
        for (uint i = 0; i < IUniswapV2Factory(factory).allPairsLength(); i++) {
            address pair = IUniswapV2Factory(factory).allPairs(i);
            if(IUniswapV2Pair(pair).balanceOf(msg.sender) > 0) {
                addresses[length++] = pair;
            }
        }
    }

    function getLiquidity(address pair)
        public
        view
        virtual
        returns (uint token0, uint token1, uint tokens, uint totalSupply, uint reserve0, uint reserve1)
    {
        IUniswapV2Pair p = IUniswapV2Pair(pair);
        token0 = p.token0();
        token1 = p.token1();
        tokens = p.balanceOf(msg.sender);
        totalSupply = p.totalSupply();
        (reserve0, reserve1) = UniswapV2Library.getReserves(factory, token0, token1);
    }

    function getBalances(uint token0, uint token1)
        public
        view
        virtual
        returns (uint balance0, uint balance1)
    {
        balance0 = balance[token0][msg.sender];
        balance1 = balance[token1][msg.sender];
    }
}
