use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

#[derive(Copy, Drop, Serde, starknet::Store)]
struct Merchant {
    merchant_id: u64,
    creator: ContractAddress,
    merchant_name: felt252,
    merchant_wallet: ContractAddress,
    is_active: bool,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct Billing {
    billing_id: felt252,
    merchant_id: u64,
    amount: u256,
    timestamp: u64,
}

#[starknet::interface]
trait IStarkashPay<TContractState> {
    fn get_merchant(self: @TContractState, merchant_id: u64) -> Merchant;
    fn create_merchant(
        ref self: TContractState, merchant_name: felt252, merchant_wallet: ContractAddress,
    ) -> u64;
    fn update_merchant_info(
        ref self: TContractState,
        merchant_id: u64,
        merchant_name: felt252,
        merchant_wallet: ContractAddress
    );
    fn deactivate_merchant(ref self: TContractState, merchant_id: u64);
    fn get_merchant_creator(self: @TContractState, merchant_id: u64) -> ContractAddress;
    fn get_merchant_name(self: @TContractState, merchant_id: u64) -> felt252;
    fn get_merchant_wallet(self: @TContractState, merchant_id: u64) -> ContractAddress;
    fn pay(
        ref self: TContractState,
        merchant_id: u64,
        billing_id: felt252,
        payment_token: ContractAddress,
        payment_amount: u256,
    );
    // fn withdraw_fee(ref self: TContractState, shop_id: u64, payment_token: ContractAddress);
    fn get_billing(self: @TContractState, billing_id: felt252) -> Billing;
}

#[starknet::contract]
pub mod StarkashPay {
    use starkashpay::interfaces::ierc20::{IERC20DispatcherTrait, IERC20Dispatcher};
    use core::num::traits::Zero;
    use super::{Merchant, Billing};
    use core::starknet::event::EventEmitter;
    use starknet::{get_caller_address, ContractAddress, get_block_timestamp, get_contract_address};

    #[storage]
    struct Storage {
        merchant_count: u64,
        all_merchant: LegacyMap::<u64, Merchant>,
        owner: ContractAddress,
        strk: ContractAddress,
        is_lock: bool,
        billing: LegacyMap::<felt252, Billing>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        MerchantCreated: MerchantCreated,
        MerchantUpdated: MerchantUpdated,
        MerchantDeactivated: MerchantDeactivated,
        Pay: Pay,
    }

    #[derive(Drop, starknet::Event)]
    struct MerchantCreated {
        merchant_id: u64,
        merchant_name: felt252,
        merchant_wallet: ContractAddress,
        creator: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct MerchantUpdated {
        merchant_id: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct MerchantDeactivated {
        merchant_id: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Pay {
        merchant_id: u64,
        billing_id: felt252,
        payment_token: ContractAddress,
        payment_amount: u256,
        timestamp: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, strk: ContractAddress) {
        self.merchant_count.write(0);
        self.owner.write(get_caller_address());
        self.strk.write(strk);
    }

    #[abi(embed_v0)]
    impl StarkashPay of super::IStarkashPay<ContractState> {
        fn get_merchant(self: @ContractState, merchant_id: u64) -> Merchant {
            self.all_merchant.read(merchant_id)
        }

        fn get_billing(self: @ContractState, billing_id: felt252) -> Billing {
            self.billing.read(billing_id)
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

        fn create_merchant(
            ref self: ContractState, merchant_name: felt252, merchant_wallet: ContractAddress
        ) -> u64 {
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
        ) {
            let merchant = self.all_merchant.read(merchant_id);
            assert(merchant.creator == get_caller_address(), 'Not owner');
            let new_merchant = Merchant {
                merchant_id: merchant.merchant_id,
                creator: merchant.creator,
                merchant_name,
                merchant_wallet,
                is_active: true,
            };
            self.all_merchant.write(merchant_id, new_merchant);
            self.emit(MerchantUpdated { merchant_id });
        }

        fn deactivate_merchant(ref self: ContractState, merchant_id: u64) {
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
        }

        fn pay(
            ref self: ContractState,
            merchant_id: u64,
            billing_id: felt252,
            payment_token: ContractAddress,
            payment_amount: u256,
        ) {
            assert(payment_token == self.strk.read(), 'Invalid token');
            self.only_unlock();
            self.lock_contract();
            let fee_percentage: u256 = 5; // Fee 0.05%
            let fee_divisor: u256 = 10000;

            let fee_amount = payment_amount * fee_percentage / fee_divisor;
            let amount_after_fee = payment_amount - fee_amount;
            let mut merchant = self.all_merchant.read(merchant_id);

            let this_contract = get_contract_address();
            let strk_contract = IERC20Dispatcher { contract_address: payment_token };
            let timestamp = get_block_timestamp();

            strk_contract.transferFrom(get_caller_address(), this_contract, payment_amount);

            if amount_after_fee > 0 {
                strk_contract.transfer(merchant.merchant_wallet, amount_after_fee);
            }

            let billing = Billing { billing_id, merchant_id, amount: payment_amount, timestamp };

            self.emit(Pay { merchant_id, billing_id, payment_token, payment_amount, timestamp });
            self.billing.write(billing_id, billing);
            self.unlock_contract();
        }
    }
    // *************************************************************************
    //                          PRIVATE FUNCTIONS
    // *************************************************************************
    #[generate_trait]
    impl Private of PrivateTrait {
        fn only_owner(ref self: ContractState) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'only owner');
        }

        fn lock_contract(ref self: ContractState) {
            self.is_lock.write(true);
        }
        fn unlock_contract(ref self: ContractState) {
            self.is_lock.write(false);
        }
        fn only_unlock(ref self: ContractState) {
            assert(self.is_lock.read() == false, 're-entrancy');
        }
    }
}
