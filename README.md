# StarkashPay

## Overview

StarkashPay is a decentralized payment gateway built on Starknet, designed to facilitate seamless transactions for merchants and peer-to-peer (P2P) payments. This smart contract provides a secure and efficient way to manage merchants, process payments, and support P2P billing.

### ClassHash

Sepolia
`0x4a05ea76beb0c1681b02f36e2a747ead4ed41c54fff2f77e218fe86e84c4424`
[StarkScan](https://sepolia.starkscan.co/class/0x4a05ea76beb0c1681b02f36e2a747ead4ed41c54fff2f77e218fe86e84c4424) | [Voyager](https://sepolia.voyager.online/class/0x4a05ea76beb0c1681b02f36e2a747ead4ed41c54fff2f77e218fe86e84c4424)

### Deployed Address

`0x1726c25b97a4132ede271f34d96b452fd436116b037d2991ef9c4f7cfe814ef`
[StarkScan](https://sepolia.starkscan.co/contract/0x1726c25b97a4132ede271f34d96b452fd436116b037d2991ef9c4f7cfe814ef) | [Voyager](https://sepolia.voyager.online/contract/0x1726c25b97a4132ede271f34d96b452fd436116b037d2991ef9c4f7cfe814ef)

## Features

- **Merchant Management**: Create, update, and deactivate merchants.
- **Payment Processing**: Handle payments to merchants with a built-in fee mechanism.
- **P2P Payments**: Facilitate direct payments between users without the need for merchant involvement.
- **Pausable and Ownable**: Contract can be paused and is controlled by an owner to ensure security.

## Structures

### Merchant

```rust
struct Merchant {
  merchant_id: u64,
  creator: ContractAddress,
  merchant_name: felt252,
  merchant_wallet: ContractAddress,
  is_active: bool
}
```

### MerchantBilling

```rust
struct MerchantBilling {
  billing_id: felt252,
  merchant_id: u64,
  payment_token: ContractAddress,
  amount: u256,
  timestamp: u64
}
```

### P2PBilling

```rust
struct P2PBilling {
  billing_id: felt252,
  payer: ContractAddress,
  receiver: ContractAddress,
  payment_token: ContractAddress,
  amount: u256,
  timestamp: u64
}
```

## Functions

### Merchant Management

```rust
// Creates a new merchant and returns the merchant ID.
create_merchant(merchant_name: felt252, merchant_wallet: ContractAddress) -> u64

// Updates the merchant’s information and returns the updated Merchant struct.
update_merchant_info(merchant_id: u64, merchant_name: felt252, merchant_wallet: ContractAddress) -> Merchant

// Deactivates a merchant and returns the merchant ID.
deactivate_merchant(merchant_id: u64) -> u64

// Retrieves the merchant’s information by ID.
get_merchant(merchant_id: u64) -> Merchant

// Returns the creator’s address of the specified merchant.
get_merchant_creator(merchant_id: u64) -> ContractAddress

// Returns the name of the specified merchant.
get_merchant_name(merchant_id: u64) -> felt252

// Returns the wallet address of the specified merchant.
get_merchant_wallet(merchant_id: u64) -> ContractAddress
```

### Billing Management

```rust
// Processes a payment to a merchant and returns the MerchantBilling struct.
pay(merchant_id: u64, billing_id: felt252, payment_token: ContractAddress, amount: u256) -> MerchantBilling

// Retrieves billing information for a specified merchant.
get_merchant_billing(billing_id: felt252) -> MerchantBilling
```

### P2P Payments

```rust
// Processes a P2P payment between users and returns the P2PBilling struct.
pay_p2p(billing_id: felt252, receiver: ContractAddress, payment_token: ContractAddress, amount: u256) -> P2PBilling

// Retrieves P2P billing information for a specified billing ID.
get_p2p_billing(billing_id: felt252) -> P2PBilling
```

### Pausable Functionality

```rust
// Pauses the contract, preventing further execution of functions.
pause()

// Unpauses the contract, allowing functions to be executed again.
unpause()
```

## Events

StarkashPay emits several events to track the state of the contract:

- **MerchantCreated**: Emitted when a new merchant is created.
- **MerchantUpdated**: Emitted when merchant information is updated.
- **MerchantDeactivated**: Emitted when a merchant is deactivated.
- **Paid**: Emitted when a payment is processed to a merchant.
- **P2PPaid**: Emitted when a P2P payment is made.

## Usage

1. Use the `create_merchant` function to register new merchants.
2. Process payments using the `pay` function for merchants and `pay_p2p` for direct payments between users.
3. Manage contract state by pausing and unpausing as needed.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
