//
//  AssetAmount.swift
//  ECHO
//
//  Created by Fedorenko Nikita on 11.07.2018.
//  Copyright © 2018 PixelPlex. All rights reserved.
//

struct AssetAmount: ECHOCodable, Decodable {
    
    enum AssetAmountCodingKeys: String, CodingKey {
        case amount
        case assetId = "asset_id"
    }
    
    var amount: UInt
    var asset: Asset
    
    init(from decoder: Decoder) throws {
        
        let values = try decoder.container(keyedBy: AssetAmountCodingKeys.self)
        amount = try values.decode(UInt.self, forKey: .amount)
        let assetId = try values.decode(String.self, forKey: .assetId)
        asset = Asset(assetId)
    }
    
    // MARK: ECHOCodable
    
    func toJSON() -> Any? {
        
        let dictionary: [AnyHashable: Any?] = [AssetAmountCodingKeys.amount.rawValue: amount,
                                               AssetAmountCodingKeys.assetId.rawValue: asset.id]
        
        return dictionary
    }
    
    func toJSON() -> String? {
        
        let json: Any? = toJSON()
        let jsonString = (json as?  [AnyHashable: Any?])
            .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [])}
            .flatMap { String(data: $0, encoding: .utf8)}
        
        return jsonString
    }
    
    func toData() -> Data? {
        
        guard let assetInstance = asset.getInstance() else {
            return nil
        }
        
        var data = Data()
        data.append(optional: Data.fromUIntLikeUnsignedByteArray(assetInstance))
        data.append(optional: Data.fromInt64(amount))
        return data
    }
}
