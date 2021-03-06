//
//  TransactionFacade.swift
//  ECHO
//
//  Created by Fedorenko Nikita on 10.07.2018.
//  Copyright © 2018 PixelPlex. All rights reserved.
//

/**
    The interface of the class that allows you to send transactions.
 */
public protocol TransactionFacade {
        
/**
     This is a function for sending funds.
     
     - Parameter fromNameOrId: Sender name or id
     - Parameter password: Sender password from account
     - Parameter toNameOrId: Receiver name or id
     - Parameter amount: Amount
     - Parameter asset: Id of asset which is sent
     - Parameter assetForFee: Id of asset which is pay fee
     - Parameter message: The message that is sent with the transaction
     - Parameter completion: Callback in which the information will return whether the transaction was successful.
     
     - Remark:
     Default asset is **"1.3.0"**
 */
    func sendTransferOperation(fromNameOrId: String,
                               password: String,
                               toNameOrId: String,
                               amount: UInt,
                               asset: String,
                               assetForFee: String?,
                               message: String?,
                               completion: @escaping Completion<Bool>)
}
