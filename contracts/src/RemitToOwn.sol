// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {USCBase} from "./USCBase.sol";
import {INativeQueryVerifier} from "./VerifierInterface.sol";
import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol";

/// @title RemitToOwn
/// @notice Pay-as-you-go device financing, paid for from another chain.
///
///         Buying a phone or a solar home system on installments is ordinary in
///         much of the world, and so is having a relative abroad cover the
///         payments. Those two facts do not currently compose: the seller is at
///         home, the money is abroad, and neither side can see the other's
///         ledger. Today that gap is filled by remittance operators and local
///         agents who each take a cut and each have to be trusted.
///
///         RemitToOwn closes it with proof instead. Every plan is issued a
///         dedicated collection address on the source chain. A relative anywhere
///         sends a stablecoin there; the Attestcoin Protocol proves that
///         transfer to Creditcoin; the plan credits itself and the device stays
///         switched on for the days that payment bought. Pay more, it runs
///         longer. Stop paying, it simply stops. When the total is covered,
///         ownership transfers.
///
///         Nothing here extends credit on reputation, so nothing here has to be
///         collected later. The only thing the contract ever needs to know is
///         whether a payment really happened on another chain, and that is
///         exactly what Attestcoin proves.
contract RemitToOwn is USCBase {
    /// @dev keccak256("Transfer(address,address,uint256)")
    bytes32 public constant TRANSFER_SIG =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    /// @dev Ten years of service per installment is already absurd; the cap
    ///      exists so day arithmetic cannot overflow the timestamp.
    uint32 public constant MAX_DAYS_PER_INSTALLMENT = 3650;

    enum Action {
        RecordPayment // 0
    }

    struct Plan {
        address buyer; // who ends up owning the device
        address merchant; // who sold it
        uint64 chainKey; // source chain payments arrive on
        address token; // stablecoin accepted (e.g. USDC on Ethereum)
        address collector; // dedicated collection address for this plan
        uint128 priceTotal; // full price, in token units
        uint128 paid; // covered so far
        uint128 installment; // nominal installment, in token units
        uint32 daysPerInstallment; // service days one installment buys
        uint64 activeUntil; // device runs until this timestamp
        bool exists;
        bool settled; // fully paid, ownership transferred
    }

    /// @notice planId => plan
    mapping(bytes32 => Plan) public plans;
    /// @notice chainKey => collection address => planId (a collector serves one plan)
    mapping(uint64 => mapping(address => bytes32)) public collectorPlan;
    /// @notice chainKey => token => accepted as real money
    mapping(uint64 => mapping(address => bool)) public trustedToken;
    /// @notice every plan ever opened
    bytes32[] public planIds;

    address public admin;

    /// @dev chainKey of the proof being processed, set for one verified call.
    uint64 private _currentChainKey;

    error InvalidAction(uint8 action);
    error UntrustedToken(uint64 chainKey, address token);
    error PlanExists(bytes32 planId);
    error NoPlan(bytes32 planId);
    error NotAdmin();
    error BadTerms();
    error DirectExecuteForbidden();

    event PlanOpened(
        bytes32 indexed planId,
        address indexed buyer,
        address indexed merchant,
        address collector,
        uint128 priceTotal,
        uint128 installment
    );
    event PaymentProven(
        bytes32 indexed planId, address indexed payer, uint128 amount, uint128 paidTotal, uint64 activeUntil
    );
    event PlanSettled(bytes32 indexed planId, address indexed buyer, uint128 paidTotal);
    event TrustedTokenSet(uint64 indexed chainKey, address indexed token, bool trusted);

    constructor() {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    // ---------------------------------------------------------------------
    // Setup
    // ---------------------------------------------------------------------

    /// @notice Accept a stablecoin on a source chain as real money. Without
    ///         this, a proven transfer of some contract's own token would count,
    ///         and anyone could mint themselves a free device.
    function setTrustedToken(uint64 chainKey, address token, bool trusted) external onlyAdmin {
        trustedToken[chainKey][token] = trusted;
        emit TrustedTokenSet(chainKey, token, trusted);
    }

    function transferAdmin(address next) external onlyAdmin {
        // Handing admin to the zero address would freeze token acceptance and
        // plan issuance for good.
        if (next == address(0)) revert BadTerms();
        admin = next;
    }

    /// @notice Open a financing plan. The collector is an address on the source
    ///         chain used by this plan alone, which is what lets a plain
    ///         stablecoin transfer (which carries no memo) be attributed.
    /// @dev    Restricted, and this is load-bearing. A proof shows that a
    ///         transfer happened; it cannot show who the recipient address
    ///         belongs to. Left open, anyone could name a busy address they do
    ///         not control (an exchange wallet, say) as their collector and
    ///         harvest a stranger's payment as their own. Issuing collectors is
    ///         therefore an operator action; the roadmap replaces it with
    ///         escrow addresses the protocol deploys itself.
    function openPlan(
        bytes32 planId,
        address buyer,
        uint64 chainKey,
        address token,
        address collector,
        uint128 priceTotal,
        uint128 installment,
        uint32 daysPerInstallment
    ) external onlyAdmin {
        if (planId == bytes32(0)) revert BadTerms();
        if (plans[planId].exists) revert PlanExists(planId);
        if (!trustedToken[chainKey][token]) revert UntrustedToken(chainKey, token);
        if (buyer == address(0) || collector == address(0)) revert BadTerms();
        if (priceTotal == 0 || installment == 0 || daysPerInstallment == 0) revert BadTerms();
        if (daysPerInstallment > MAX_DAYS_PER_INSTALLMENT) revert BadTerms();
        if (collectorPlan[chainKey][collector] != bytes32(0)) revert BadTerms();

        plans[planId] = Plan({
            buyer: buyer,
            merchant: msg.sender,
            chainKey: chainKey,
            token: token,
            collector: collector,
            priceTotal: priceTotal,
            paid: 0,
            installment: installment,
            daysPerInstallment: daysPerInstallment,
            activeUntil: 0,
            exists: true,
            settled: false
        });
        collectorPlan[chainKey][collector] = planId;
        planIds.push(planId);

        emit PlanOpened(planId, buyer, msg.sender, collector, priceTotal, installment);
    }

    // ---------------------------------------------------------------------
    // Proof path: recordPayment -> USCBase.execute -> _processAndEmitEvent
    // ---------------------------------------------------------------------

    /// @notice Prove one source-chain payment and credit the plan it belongs to.
    /// @dev Wraps USCBase.execute so the origin check knows the source chain.
    ///      USCBase is kept as published, so the chain key travels via storage.
    function recordPayment(
        uint64 chainKey,
        uint64 blockHeight,
        bytes calldata encodedTransaction,
        bytes32 merkleRoot,
        INativeQueryVerifier.MerkleProofEntry[] calldata siblings,
        bytes32 lowerEndpointDigest,
        bytes32[] calldata continuityRoots
    ) external returns (bool) {
        _setChainKey(chainKey);
        bool ok = this.execute(
            uint8(Action.RecordPayment),
            chainKey,
            blockHeight,
            encodedTransaction,
            merkleRoot,
            siblings,
            lowerEndpointDigest,
            continuityRoots
        );
        _setChainKey(0);
        return ok;
    }

    /// @dev The chain key of the proof in flight. USCBase is kept exactly as
    ///      published and hands the child only the decoded transaction, so the
    ///      key travels through storage for the length of one verified call.
    function _setChainKey(uint64 chainKey) internal {
        _currentChainKey = chainKey;
    }

    function _processAndEmitEvent(uint8 action, bytes32, bytes memory encodedTransaction) internal override {
        if (action != uint8(Action.RecordPayment)) revert InvalidAction(action);
        // execute() is external on the base, so it can be called directly with
        // no chain key set. Payments must come through recordPayment.
        if (_currentChainKey == 0) revert DirectExecuteForbidden();

        uint8 txType = EvmV1Decoder.getTransactionType(encodedTransaction);
        require(EvmV1Decoder.isValidTransactionType(txType), "Unsupported transaction type");

        EvmV1Decoder.ReceiptFields memory receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        require(receipt.receiptStatus == 1, "Transaction did not succeed");

        EvmV1Decoder.LogEntry[] memory transfers = EvmV1Decoder.getLogsByEventSignature(receipt, TRANSFER_SIG);
        require(transfers.length > 0, "No transfer events found");

        // One transaction can pay several plans at once (a batch payout), so
        // credit every transfer that lands on a collection address we know.
        uint256 credited = 0;
        for (uint256 i = 0; i < transfers.length; i++) {
            EvmV1Decoder.LogEntry memory log = transfers[i];
            if (log.topics.length != 3) continue;
            if (
                _creditTransferLog(
                    log.address_,
                    address(uint160(uint256(log.topics[1]))),
                    address(uint160(uint256(log.topics[2]))),
                    log.data.length >= 32 ? abi.decode(log.data, (uint256)) : 0
                )
            ) {
                credited++;
            }
        }
        require(credited > 0, "No payment to a known plan");
    }

    /// @dev Decide whether one proven ERC-20 transfer counts as a payment, and
    ///      credit it if so. Everything a transfer must satisfy lives here, in
    ///      one place, so the rules can be read and tested on their own.
    function _creditTransferLog(address emitter, address from, address to, uint256 amount)
        internal
        returns (bool)
    {
        bytes32 planId = collectorPlan[_currentChainKey][to];
        if (planId == bytes32(0)) return false; // not a collection address we know

        Plan storage p = plans[planId];

        // The plan states which chain and which token it is paid in, and both
        // must match. Without this, any accepted token would credit any plan,
        // so a token with different decimals could settle a plan for a
        // rounding error.
        if (p.chainKey != _currentChainKey) return false;
        if (emitter != p.token) return false;

        // A payment transaction routinely carries other tokens to the same
        // address, because swaps route several assets at once. Anything that is
        // not accepted money is simply not a payment.
        if (!trustedToken[_currentChainKey][emitter]) return false;

        // Already paid off. Crediting further would be meaningless and
        // swallowing it silently would be worse.
        if (p.settled) return false;

        // An address paying itself moves no money, whatever the log says.
        if (from == to) return false;

        // Reject rather than truncate: a value above uint128 would wrap to
        // something small, or to zero, and be credited as though it were real.
        if (amount == 0 || amount > type(uint128).max) return false;

        _applyPayment(planId, from, uint128(amount));
        return true;
    }

    // ---------------------------------------------------------------------
    // Rule layer: pure state logic, unit-testable without precompile or decoder
    // ---------------------------------------------------------------------

    function _applyPayment(bytes32 planId, address payer, uint128 amount) internal {
        Plan storage p = plans[planId];
        if (!p.exists) revert NoPlan(planId);

        // Service time scales with the amount, so a relative can send half an
        // installment or three at once and the device responds accordingly.
        // Accrued in seconds, not days: in this market people send small sums,
        // and rounding those down to zero days would quietly eat them.
        uint256 secondsBought = (uint256(amount) * uint256(p.daysPerInstallment) * 1 days) / p.installment;
        uint256 base = p.activeUntil > block.timestamp ? p.activeUntil : block.timestamp;
        uint256 until = base + secondsBought;
        p.activeUntil = until > type(uint64).max ? type(uint64).max : uint64(until);

        uint128 remainingDue = p.priceTotal > p.paid ? p.priceTotal - p.paid : 0;
        p.paid = amount >= remainingDue ? p.priceTotal : p.paid + amount;

        emit PaymentProven(planId, payer, amount, p.paid, p.activeUntil);

        if (!p.settled && p.paid >= p.priceTotal) {
            p.settled = true;
            // Once the price is covered the device is the buyer's outright and
            // never switches off again.
            p.activeUntil = type(uint64).max;
            emit PlanSettled(planId, p.buyer, p.paid);
        }
    }

    // ---------------------------------------------------------------------
    // Read API: what a device or a shop actually calls
    // ---------------------------------------------------------------------

    /// @notice Should this device be running right now.
    function isActive(bytes32 planId) external view returns (bool) {
        Plan storage p = plans[planId];
        return p.exists && p.activeUntil > block.timestamp;
    }

    /// @notice Seconds of service left, zero if lapsed.
    function timeRemaining(bytes32 planId) external view returns (uint64) {
        Plan storage p = plans[planId];
        if (!p.exists || p.activeUntil <= block.timestamp) return 0;
        return p.activeUntil - uint64(block.timestamp);
    }

    function amountRemaining(bytes32 planId) external view returns (uint128) {
        Plan storage p = plans[planId];
        if (!p.exists) return 0;
        return p.priceTotal > p.paid ? p.priceTotal - p.paid : 0;
    }

    function getPlan(bytes32 planId)
        external
        view
        returns (
            address buyer,
            address merchant,
            address collector,
            uint128 priceTotal,
            uint128 paid,
            uint64 activeUntil,
            bool active,
            bool settled
        )
    {
        Plan storage p = plans[planId];
        return (
            p.buyer,
            p.merchant,
            p.collector,
            p.priceTotal,
            p.paid,
            p.activeUntil,
            p.exists && p.activeUntil > block.timestamp,
            p.settled
        );
    }

    /// @notice Which chain and token this plan is paid in. Exposed so an
    ///         interface can show what a payer must actually send, and where.
    function getPlanCurrency(bytes32 planId)
        external
        view
        returns (uint64 chainKey, address token, uint128 installment, uint32 daysPerInstallment)
    {
        Plan storage p = plans[planId];
        return (p.chainKey, p.token, p.installment, p.daysPerInstallment);
    }

    function planCount() external view returns (uint256) {
        return planIds.length;
    }
}
