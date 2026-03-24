import Foundation

struct FoodItem: Codable, Identifiable {
    let id: UUID
    let name: String
    let type: FoodItemType
    let quantity: String
    let quantityMl: Int?
    let hasNutritionLabel: Bool
    let needsManualEntry: Bool
    let confidence: Double

    enum FoodItemType: String, Codable {
        case packaged
        case dish
        case drink
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decode(FoodItemType.self, forKey: .type)
        self.quantity = try container.decode(String.self, forKey: .quantity)
        self.quantityMl = try container.decodeIfPresent(Int.self, forKey: .quantityMl)
        self.hasNutritionLabel = try container.decode(Bool.self, forKey: .hasNutritionLabel)
        self.needsManualEntry = try container.decode(Bool.self, forKey: .needsManualEntry)
        self.confidence = try container.decode(Double.self, forKey: .confidence)
    }

    enum CodingKeys: String, CodingKey {
        case name, type, quantity
        case quantityMl = "quantity_ml"
        case hasNutritionLabel = "has_nutrition_label"
        case needsManualEntry = "needs_manual_entry"
        case confidence
    }
}

struct FoodAnalysisResult: Codable {
    let items: [FoodItem]
}
