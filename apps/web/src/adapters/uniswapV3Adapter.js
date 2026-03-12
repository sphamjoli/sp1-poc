export class UniswapV3Adapter {
    mode = "uniswap";
    async getBalance(_wallet, _token) {
        throw new Error("Uniswap adapter not configured. Set RPC + wallet integration first.");
    }
    async getAllowance(_wallet, _spender, _token) {
        throw new Error("Uniswap adapter not configured. Set RPC + wallet integration first.");
    }
    async quote(_request) {
        throw new Error("Uniswap quote path is not configured yet.");
    }
    async approve(_wallet, _spender, _token, _amount) {
        throw new Error("Uniswap approve path is not configured yet.");
    }
    async swap(_wallet, _request) {
        throw new Error("Uniswap swap path is not configured yet.");
    }
}
