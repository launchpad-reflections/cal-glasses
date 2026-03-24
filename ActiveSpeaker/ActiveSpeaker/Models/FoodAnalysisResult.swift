import UIKit

struct FoodItem: Codable, Identifiable {
    let id: UUID
    let name: String
    let type: FoodItemType
    let quantity: String
    let portions: Double
    let calories: Int?
    let quantityMl: Int?
    let hasNutritionLabel: Bool
    let needsManualEntry: Bool
    let confidence: Double
    let bestImageIndex: Int?
    let nutritionSummary: String?

    /// The actual UIImage for this item (set after decoding, not from JSON).
    var image: UIImage?

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
        self.portions = try container.decodeIfPresent(Double.self, forKey: .portions) ?? 1.0
        self.calories = try container.decodeIfPresent(Int.self, forKey: .calories)
        self.quantityMl = try container.decodeIfPresent(Int.self, forKey: .quantityMl)
        self.hasNutritionLabel = try container.decode(Bool.self, forKey: .hasNutritionLabel)
        self.needsManualEntry = try container.decode(Bool.self, forKey: .needsManualEntry)
        self.confidence = try container.decode(Double.self, forKey: .confidence)
        self.bestImageIndex = try container.decodeIfPresent(Int.self, forKey: .bestImageIndex)
        self.nutritionSummary = try container.decodeIfPresent(String.self, forKey: .nutritionSummary)
        self.image = nil
    }

    enum CodingKeys: String, CodingKey {
        case name, type, quantity, portions, calories
        case quantityMl = "quantity_ml"
        case hasNutritionLabel = "has_nutrition_label"
        case needsManualEntry = "needs_manual_entry"
        case confidence
        case bestImageIndex = "best_image_index"
        case nutritionSummary = "nutrition_summary"
    }
}

struct FoodAnalysisResult: Codable {
    var items: [FoodItem]

    /// Attach the actual UIImages to each food item based on bestImageIndex.
    mutating func attachImages(from frames: [UIImage]) {
        for i in items.indices {
            if let idx = items[i].bestImageIndex, idx >= 0, idx < frames.count {
                items[i].image = frames[idx]
            } else if !frames.isEmpty {
                items[i].image = frames[0]
            }
        }
    }
}
