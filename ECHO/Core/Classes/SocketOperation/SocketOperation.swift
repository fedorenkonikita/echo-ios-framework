//
//  SocketOperation.swift
//  ECHO
//
//  Created by Fedorenko Nikita on 10.07.2018.
//  Copyright © 2018 PixelPlex. All rights reserved.
//

/**
    Method type for call to blockchain
 */
enum SocketOperationType: String {
    case call
    case notice
}

/**
    Represents blockchain operations by keys
 */
enum SocketOperationKeys: String {
    case blockData = "get_dynamic_global_properties"
    case fullAccount = "get_full_accounts"
    case accountHistory = "get_account_history"
    case assets = "get_assets"
    case block = "get_block"
    case chainId = "get_chain_id"
    case contractResult = "get_contract_result"
    case object = "get_objects"
    case keyReference = "get_key_references"
    case requiredFee = "get_required_fees"
    case subscribeCallback = "set_subscribe_callback"
    case setBlockAppliedCallback = "set_block_applied_callback"
    case transaction = "broadcast_transaction_with_callback"
    case listAssets = "list_assets"
    case getAllContracts = "get_all_contracts"
    case getContracts = "get_contracts"
    case getContract = "get_contract"
    case callContractNoChangingState = "call_contract_no_changing_state"
}

typealias OperationResult<T> = (operation: SocketOperation, result: Result<T, ECHOError>)

/**
    Represents blockchain call [Source](http://docs.bitshares.org/api/rpc.html)
 */
protocol SocketOperation: JSONCodable {
    
    var method: SocketOperationType { get }
    var operationId: Int { get }
    var apiId: Int { get }
    func createParameters() -> [Any]
    func complete(json: [String: Any])
    func forceEnd()
}

/**
    Keys for json creation of blockchain call
 */
enum OperationCodingKeys: String, CodingKey {
    case method
    case params
    case id
}

extension SocketOperation {

    func toJSON() -> Any? {

        let dictionary: [AnyHashable: Any] = [OperationCodingKeys.method.rawValue: method.rawValue,
                                              OperationCodingKeys.id.rawValue: operationId,
                                              OperationCodingKeys.params.rawValue: createParameters()]

        return dictionary
    }
    
    func forceEnd() { }
}
