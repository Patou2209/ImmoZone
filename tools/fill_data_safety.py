#!/usr/bin/env python3
"""Génère le CSV Data Safety Play Store pour ImmoZone à partir du sample Google."""
import csv

SRC = "/home/user/uploaded_files/data_safety_sample.csv"
DST = "/home/user/webapp/tools/immozone_data_safety.csv"

DELETION_URL = "https://immozone.pro/account-deletion"

# Types de données déclarés : (data_type_id, user_control, purposes)
# user_control: "REQUIRED" ou "OPTIONAL"
DECLARED = {
    "PSL_NAME":                 ("REQUIRED", ["PSL_APP_FUNCTIONALITY", "PSL_ACCOUNT_MANAGEMENT"]),
    "PSL_EMAIL":                ("OPTIONAL", ["PSL_ACCOUNT_MANAGEMENT"]),
    "PSL_PHONE":                ("REQUIRED", ["PSL_APP_FUNCTIONALITY", "PSL_ACCOUNT_MANAGEMENT", "PSL_FRAUD_PREVENTION_SECURITY"]),
    "PSL_USER_ACCOUNT":         ("REQUIRED", ["PSL_APP_FUNCTIONALITY", "PSL_ACCOUNT_MANAGEMENT"]),
    "PSL_ADDRESS":              ("OPTIONAL", ["PSL_APP_FUNCTIONALITY"]),
    "PSL_PHOTOS":               ("OPTIONAL", ["PSL_APP_FUNCTIONALITY"]),
    "PSL_OTHER_MESSAGES":       ("OPTIONAL", ["PSL_APP_FUNCTIONALITY"]),
    "PSL_PURCHASE_HISTORY":     ("OPTIONAL", ["PSL_APP_FUNCTIONALITY", "PSL_FRAUD_PREVENTION_SECURITY"]),
    "PSL_USER_GENERATED_CONTENT": ("OPTIONAL", ["PSL_APP_FUNCTIONALITY"]),
}

# Mapping type -> question de la section "Types de données" (PSL_DATA_TYPES_*)
TYPE_SECTION = {
    "PSL_NAME": "PSL_DATA_TYPES_PERSONAL",
    "PSL_EMAIL": "PSL_DATA_TYPES_PERSONAL",
    "PSL_PHONE": "PSL_DATA_TYPES_PERSONAL",
    "PSL_USER_ACCOUNT": "PSL_DATA_TYPES_PERSONAL",
    "PSL_ADDRESS": "PSL_DATA_TYPES_PERSONAL",
    "PSL_PHOTOS": "PSL_DATA_TYPES_PHOTOS_AND_VIDEOS",
    "PSL_OTHER_MESSAGES": "PSL_DATA_TYPES_EMAIL_AND_TEXT",
    "PSL_PURCHASE_HISTORY": "PSL_DATA_TYPES_FINANCIAL",
    "PSL_USER_GENERATED_CONTENT": "PSL_DATA_TYPES_APP_ACTIVITY",
}

rows_out = []
with open(SRC, newline="", encoding="utf-8") as f:
    reader = csv.reader(f)
    header = next(reader)
    rows_out.append(header)
    for row in reader:
        if len(row) < 5:
            rows_out.append(row)
            continue
        qid, rid, val, req, label = row[0], row[1], row[2], row[3], row[4]
        newval = ""  # on repart de zéro (le sample contient des valeurs d'exemple)

        # ── Questions générales ──────────────────────────────────────────
        if qid == "PSL_DATA_COLLECTION_COLLECTS_PERSONAL_DATA":
            newval = "true"
        elif qid == "PSL_DATA_COLLECTION_ENCRYPTED_IN_TRANSIT":
            newval = "true"   # Firebase = HTTPS/TLS partout
        elif qid == "PSL_SUPPORTED_ACCOUNT_CREATION_METHODS":
            # Téléphone + mot de passe + OTP SMS
            newval = "true" if rid == "PSL_ACM_USER_ID_PASSWORD_OTHER_AUTH" else ""
        elif qid == "PSL_ACM_SPECIFY":
            newval = ("Création de compte avec numéro de téléphone et mot de passe, "
                      "vérifiée par code OTP envoyé par SMS (Firebase Authentication).")
        elif qid == "PSL_ACCOUNT_DELETION_URL":
            newval = DELETION_URL
        elif qid == "PSL_SUPPORT_DATA_DELETION_BY_USER":
            newval = "true" if rid == "DATA_DELETION_YES" else ""
        elif qid == "PSL_DATA_DELETION_URL":
            newval = DELETION_URL
        elif qid == "PSL_HAS_OUTSIDE_APP_ACCOUNTS":
            newval = "false"

        # ── Section "Types de données" : cocher les types collectés ─────
        elif qid in set(TYPE_SECTION.values()):
            declared_here = [t for t, sec in TYPE_SECTION.items() if sec == qid]
            newval = "true" if rid in declared_here else ""

        # ── Section "Utilisation et traitement" par type déclaré ────────
        elif qid.startswith("PSL_DATA_USAGE_RESPONSES:"):
            parts = qid.split(":")
            dtype, subq = parts[1], parts[2]
            if dtype in DECLARED:
                control, purposes = DECLARED[dtype]
                if subq == "PSL_DATA_USAGE_COLLECTION_AND_SHARING":
                    newval = "true" if rid == "PSL_DATA_USAGE_ONLY_COLLECTED" else ""
                elif subq == "PSL_DATA_USAGE_EPHEMERAL":
                    newval = "false"
                elif subq == "DATA_USAGE_USER_CONTROL":
                    want = ("PSL_DATA_USAGE_USER_CONTROL_REQUIRED"
                            if control == "REQUIRED"
                            else "PSL_DATA_USAGE_USER_CONTROL_OPTIONAL")
                    newval = "true" if rid == want else ""
                elif subq == "DATA_USAGE_COLLECTION_PURPOSE":
                    newval = "true" if rid in purposes else ""
                elif subq == "DATA_USAGE_SHARING_PURPOSE":
                    newval = ""  # rien n'est partagé avec des tiers
            else:
                newval = ""  # type non déclaré : tout vide

        rows_out.append([qid, rid, newval, req, label])

with open(DST, "w", newline="", encoding="utf-8") as f:
    csv.writer(f, lineterminator="\r\n").writerows(rows_out)

# Résumé
n_true = sum(1 for r in rows_out if len(r) > 2 and r[2] == "true")
print(f"OK — {len(rows_out)-1} lignes écrites, {n_true} réponses 'true' → {DST}")
