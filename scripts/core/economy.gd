class_name Economy
extends RefCounted
## The books: cash, this month's income and costs by category, and history.

signal changed()

const INCOME_NAMES := {
	"green_fees": "Green fees", "concessions": "Drink stands", "pro_shop": "Pro shop",
	"tournaments": "Tournaments", "events": "Events and sponsors", "memberships": "Membership dues",
	"real_estate": "Homes and lots", "carts": "Cart rental", "range": "Driving range",
}
const EXPENSE_NAMES := {
	"construction": "Construction", "wages": "Staff wages", "upkeep": "Upkeep",
	"purses": "Tournament purses", "legal": "Legal", "equipment": "Your equipment", "land": "Land", "interest": "Interest on debt", "wagers": "Lost wagers",
}

var money := 0.0
var income := {}
var expense := {}
var history: Array[Dictionary] = []
var lifetime_income := 0.0


func earn(cat: String, amount: float) -> void:
	if amount <= 0.0:
		return
	money += amount
	lifetime_income += amount
	income[cat] = float(income.get(cat, 0.0)) + amount
	changed.emit()


func spend(cat: String, amount: float) -> void:
	if amount <= 0.0:
		return
	money -= amount
	expense[cat] = float(expense.get(cat, 0.0)) + amount
	changed.emit()


func can_afford(amount: float) -> bool:
	return money >= amount


static func total(d: Dictionary) -> float:
	var t := 0.0
	for k: String in d:
		t += float(d[k])
	return t


func net() -> float:
	return total(income) - total(expense)


func close_month(label: String, rating: float = -1.0, satisfaction: float = -1.0) -> void:
	var row := {"label": label, "income": income.duplicate(), "expense": expense.duplicate(), "net": net(), "money": money}
	if rating >= 0.0:
		row["rating"] = rating
	if satisfaction >= 0.0:
		row["satisfaction"] = satisfaction
	history.append(row)
	if history.size() > 24:
		history.pop_front()
	income = {}
	expense = {}
	changed.emit()
