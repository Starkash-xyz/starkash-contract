use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, starknet::Store)]
struct Merchant {
    merchant_id: u64,
    creator: ContractAddress,
    merchant_name: felt252,
    merchant_wallet: ContractAddress,
    is_active: bool
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct MerchantBilling {
    billing_id: felt252,
    merchant_id: u64,
    payment_token: ContractAddress,
    amount: u256,
    timestamp: u64
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct P2PBilling {
    billing_id: felt252,
    payer: ContractAddress,
    receiver: ContractAddress,
    payment_token: ContractAddress,
    amount: u256,
    timestamp: u64
}

#[starknet::interface]
trait IStarkashPay<TContractState> {
    fn get_merchant(self: @TContractState, merchant_id: u64) -> Merchant;
    fn get_merchant_creator(self: @TContractState, merchant_id: u64) -> ContractAddress;
    fn get_merchant_name(self: @TContractState, merchant_id: u64) -> felt252;
    fn get_merchant_wallet(self: @TContractState, merchant_id: u64) -> ContractAddress;
    fn get_merchant_billing(self: @TContractState, billing_id: felt252) -> MerchantBilling;
    fn get_payment_token(self: @TContractState) -> ContractAddress;
    fn get_p2p_billing(self: @TContractState, billing_id: felt252) -> P2PBilling;
    fn create_merchant(
        ref self: TContractState, merchant_name: felt252, merchant_wallet: ContractAddress,
    ) -> u64;
    fn update_merchant_info(
        ref self: TContractState,
        merchant_id: u64,
        merchant_name: felt252,
        merchant_wallet: ContractAddress
    ) -> Merchant;
    fn deactivate_merchant(ref self: TContractState, merchant_id: u64) -> u64;
    fn pay(
        ref self: TContractState,
        merchant_id: u64,
        billing_id: felt252,
        payment_token: ContractAddress,
        amount: u256,
    ) -> MerchantBilling;
    fn pay_p2p(
        ref self: TContractState,
        billing_id: felt252,
        receiver: ContractAddress,
        payment_token: ContractAddress,
        amount: u256,
    ) -> P2PBilling;
    fn claim_fee(ref self: TContractState) -> u256;
}

#[starknet::contract]
pub mod StarkashPay {
    use starkashpay::interfaces::ierc20::{IERC20DispatcherTrait, IERC20Dispatcher};
    use core::num::traits::Zero;
    use super::{Merchant, MerchantBilling, P2PBilling};
    use core::starknet::event::EventEmitter;
    use starknet::{get_caller_address, ContractAddress, get_block_timestamp, get_contract_address};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerWriteAccess,
        StoragePointerReadAccess
    };

    use openzeppelin::security::PausableComponent;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::security::ReentrancyGuardComponent;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(
        path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent
    );

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    impl InternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        merchant_count: u64,
        all_merchant: Map::<u64, Merchant>,
        payment_token: ContractAddress,
        merchant_billing: Map::<felt252, MerchantBilling>,
        p2p_billing: Map::<felt252, P2PBilling>,
        total_fees_collected: u256,
        total_fees_claimed: u256,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        MerchantCreated: MerchantCreated,
        MerchantUpdated: MerchantUpdated,
        MerchantDeactivated: MerchantDeactivated,
        Paid: Paid,
        P2PPaid: P2PPaid,
        FeeClaimed: FeeClaimed,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event
    }

    #[derive(Drop, starknet::Event)]
    struct MerchantCreated {
        merchant_id: u64,
        merchant_name: felt252,
        merchant_wallet: ContractAddress,
        creator: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct MerchantUpdated {
        merchant_id: u64
    }

    #[derive(Drop, starknet::Event)]
    struct MerchantDeactivated {
        merchant_id: u64
    }

    #[derive(Drop, starknet::Event)]
    struct Paid {
        merchant_id: u64,
        billing_id: felt252,
        payment_token: ContractAddress,
        amount: u256,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct P2PPaid {
        billing_id: felt252,
        receiver: ContractAddress,
        payer: ContractAddress,
        payment_token: ContractAddress,
        amount: u256,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct FeeClaimed {
        amount: u256,
        timestamp: u64
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, payment_token: ContractAddress) {
        assert(Zero::is_non_zero(@owner), 'Owner address zero');
        assert(Zero::is_non_zero(@payment_token), 'Payment token address zero');
        self.ownable.initializer(owner);
        self.payment_token.write(payment_token);
        self.merchant_count.write(0);
    }

    #[external(v0)]
    fn pause(ref self: ContractState) {
        self.ownable.assert_only_owner();
        self.pausable.pause();
    }

    #[external(v0)]
    fn unpause(ref self: ContractState) {
        self.ownable.assert_only_owner();
        self.pausable.unpause();
    }

    #[abi(embed_v0)]
    impl StarkashPay of super::IStarkashPay<ContractState> {
        fn get_merchant(self: @ContractState, merchant_id: u64) -> Merchant {
            self.all_merchant.read(merchant_id)
        }

        fn get_merchant_billing(self: @ContractState, billing_id: felt252) -> MerchantBilling {
            self.merchant_billing.read(billing_id)
        }

        fn get_p2p_billing(self: @ContractState, billing_id: felt252) -> P2PBilling {
            self.p2p_billing.read(billing_id)
        }

        fn get_merchant_creator(self: @ContractState, merchant_id: u64) -> ContractAddress {
            let merchant = self.all_merchant.read(merchant_id);
            merchant.creator
        }

        fn get_merchant_name(self: @ContractState, merchant_id: u64) -> felt252 {
            let merchant = self.all_merchant.read(merchant_id);
            merchant.merchant_name
        }

        fn get_merchant_wallet(self: @ContractState, merchant_id: u64) -> ContractAddress {
            let merchant = self.all_merchant.read(merchant_id);
            merchant.merchant_wallet
        }

        fn get_payment_token(self: @ContractState) -> ContractAddress {
            let payment_token = self.payment_token.read();
            payment_token
        }

        fn create_merchant(
            ref self: ContractState, merchant_name: felt252, merchant_wallet: ContractAddress
        ) -> u64 {
            self.pausable.assert_not_paused();
            assert(Zero::is_non_zero(@merchant_wallet), 'Merchant address zero');

            let merchant_id = self.merchant_count.read() + 1;
            let creator = get_caller_address();
            let merchant = Merchant {
                merchant_id, creator, merchant_name, merchant_wallet, is_active: true,
            };
            self.all_merchant.write(merchant_id, merchant);
            self.merchant_count.write(merchant_id + 1);
            self.emit(MerchantCreated { merchant_id, merchant_name, merchant_wallet, creator });
            merchant_id
        }

        fn update_merchant_info(
            ref self: ContractState,
            merchant_id: u64,
            merchant_name: felt252,
            merchant_wallet: ContractAddress
        ) -> Merchant {
            self.pausable.assert_not_paused();

            let merchant = self.all_merchant.read(merchant_id);
            assert(merchant.creator == get_caller_address(), 'Not owner');
            assert(Zero::is_non_zero(@merchant_wallet), 'Merchant address zero');
            let new_merchant = Merchant {
                merchant_id: merchant.merchant_id,
                creator: merchant.creator,
                merchant_name,
                merchant_wallet,
                is_active: true
            };
            self.all_merchant.write(merchant_id, new_merchant);
            self.emit(MerchantUpdated { merchant_id });
            new_merchant
        }

        fn deactivate_merchant(ref self: ContractState, merchant_id: u64) -> u64 {
            self.pausable.assert_not_paused();

            let merchant = self.all_merchant.read(merchant_id);
            assert(merchant.creator == get_caller_address(), 'Not owner');
            let new_merchant = Merchant {
                merchant_id,
                creator: Zero::zero(),
                merchant_name: '0',
                merchant_wallet: Zero::zero(),
                is_active: false
            };
            self.all_merchant.write(merchant_id, new_merchant);
            self.emit(MerchantDeactivated { merchant_id });
            merchant_id
        }

        fn pay(
            ref self: ContractState,
            merchant_id: u64,
            billing_id: felt252,
            payment_token: ContractAddress,
            amount: u256
        ) -> MerchantBilling {
            self.pausable.assert_not_paused();

            let mut merchant = self.all_merchant.read(merchant_id);
            assert(merchant.is_active, 'Merchant is inactive');
            assert(amount > 0, 'Amount must be > 0');
            assert(payment_token == self.payment_token.read(), 'Invalid token');

            let existing_merchant_billing_id = self.merchant_billing.read((billing_id));
            assert(existing_merchant_billing_id.billing_id == 0, 'Billing ID already exists');

            let fee_percentage: u256 = 5; // Fee 0.05%
            let fee_divisor: u256 = 10000;

            let fee_amount = amount * fee_percentage / fee_divisor;
            let amount_after_fee = amount - fee_amount;

            let this_contract = get_contract_address();
            let strk_contract = IERC20Dispatcher { contract_address: payment_token };
            let timestamp = get_block_timestamp();
            self.reentrancy_guard.start();

            let billing = MerchantBilling {
                billing_id, merchant_id, payment_token, amount: amount, timestamp
            };
            self.total_fees_collected.write(self.total_fees_collected.read() + fee_amount);
            self.merchant_billing.write(billing_id, billing);
            strk_contract.transferFrom(get_caller_address(), this_contract, amount);

            if amount_after_fee > 0 {
                strk_contract.transfer(merchant.merchant_wallet, amount_after_fee);
            }
            self.emit(Paid { merchant_id, billing_id, payment_token, amount, timestamp });
            self.reentrancy_guard.end();
            billing
        }

        fn pay_p2p(
            ref self: ContractState,
            billing_id: felt252,
            receiver: ContractAddress,
            payment_token: ContractAddress,
            amount: u256
        ) -> P2PBilling {
            self.pausable.assert_not_paused();

            assert(payment_token == self.payment_token.read(), 'Invalid token');
            assert(Zero::is_non_zero(@receiver), 'Receiver address zero');
            assert(amount > 0, 'Amount must be > 0');

            let existing_p2p_billing_id = self.p2p_billing.read((billing_id));
            assert(existing_p2p_billing_id.billing_id == 0, 'Billing ID already exists');

            let strk_contract = IERC20Dispatcher { contract_address: payment_token };
            let payer = get_caller_address();
            let timestamp = get_block_timestamp();
            self.reentrancy_guard.start();

            let billing = P2PBilling {
                billing_id, payer, receiver, payment_token, amount, timestamp
            };
            self.p2p_billing.write(billing_id, billing);
            strk_contract.transferFrom(payer, receiver, amount);
            self.emit(P2PPaid { billing_id, receiver, payer, payment_token, amount, timestamp });

            self.reentrancy_guard.end();
            billing
        }

        fn claim_fee(ref self: ContractState) -> u256 {
            self.pausable.assert_not_paused();
            self.ownable.assert_only_owner();

            let caller = get_caller_address();
            assert(self.total_fees_collected.read() > self.total_fees_claimed.read(), 'No fees to claim');

            let claimable_amount = self.total_fees_collected.read() - self.total_fees_claimed.read();
            assert(claimable_amount > 0, 'No fees available for claim');
            let timestamp = get_block_timestamp();
            let strk_contract = IERC20Dispatcher { contract_address: self.payment_token.read() };
            self.reentrancy_guard.start();

            self.total_fees_claimed.write(self.total_fees_claimed.read() + claimable_amount);
            strk_contract.transfer(caller, claimable_amount);
            self.emit(FeeClaimed {amount: claimable_amount, timestamp});

            self.reentrancy_guard.end();
            claimable_amount
        }
    }
}
