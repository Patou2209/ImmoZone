# -*- coding: utf-8 -*-
"""Génère le Manuel Utilisateur ImmoZone (formation agents) en .docx"""
from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

PRIMARY = RGBColor(0x1A, 0x3C, 0x6E)   # bleu ImmoZone
ACCENT  = RGBColor(0xE8, 0x7A, 0x00)   # orange

doc = Document()

# Styles de base
st = doc.styles['Normal']
st.font.name = 'Calibri'
st.font.size = Pt(11)

for lvl, size in [('Heading 1', 16), ('Heading 2', 13)]:
    h = doc.styles[lvl]
    h.font.name = 'Calibri'
    h.font.size = Pt(size)
    h.font.color.rgb = PRIMARY
    h.font.bold = True

def h1(txt):
    p = doc.add_heading(txt, level=1)
    return p

def h2(txt):
    return doc.add_heading(txt, level=2)

def para(txt, bold=False, size=None, color=None, align=None):
    p = doc.add_paragraph()
    r = p.add_run(txt)
    r.bold = bold
    if size: r.font.size = Pt(size)
    if color: r.font.color.rgb = color
    if align: p.alignment = align
    return p

def bullet(txt, bold_prefix=None):
    p = doc.add_paragraph(style='List Bullet')
    if bold_prefix:
        r = p.add_run(bold_prefix)
        r.bold = True
        p.add_run(txt)
    else:
        p.add_run(txt)
    return p

def step(txt, bold_prefix=None):
    p = doc.add_paragraph(style='List Number')
    if bold_prefix:
        r = p.add_run(bold_prefix)
        r.bold = True
        p.add_run(txt)
    else:
        p.add_run(txt)
    return p

def note(txt, label="💡 Astuce : "):
    p = doc.add_paragraph()
    r = p.add_run(label)
    r.bold = True
    r.font.color.rgb = ACCENT
    p.add_run(txt)
    return p

def new_numbering():
    """Force un nouveau départ de numérotation en insérant un paragraphe vide stylé."""
    pass  # python-docx réutilise la liste ; on sépare les étapes par sections H2, lisible en formation

# ───────────────────────── PAGE DE GARDE ─────────────────────────
para('', size=28)
para('IMMOZONE', bold=True, size=36, color=PRIMARY, align=WD_ALIGN_PARAGRAPH.CENTER)
para('Manuel Utilisateur', bold=True, size=22, color=ACCENT, align=WD_ALIGN_PARAGRAPH.CENTER)
para('Guide de formation — Annonceurs & Visiteurs', size=13, align=WD_ALIGN_PARAGRAPH.CENTER)
para('', size=14)
para('Achetez, Vendez, Louez un bien immobilier en quelques clics', size=11,
     align=WD_ALIGN_PARAGRAPH.CENTER)
para('', size=14)
para('📱 Android : Play Store — « ImmoZone »', bold=True, size=12, align=WD_ALIGN_PARAGRAPH.CENTER)
para('🌐 Web : www.immozone.pro', bold=True, size=12, align=WD_ALIGN_PARAGRAPH.CENTER)
para('', size=12)
para('Version 1.0 — Novembre 2026', size=10, align=WD_ALIGN_PARAGRAPH.CENTER)
doc.add_page_break()

# ───────────────────────── 1. INSTALLATION ─────────────────────────
h1('1. Installation de l\u2019application')
para('ImmoZone est disponible sur deux canaux :')
bullet('sur le Play Store, sous le nom « ImmoZone » — recherchez, installez, ouvrez.',
       bold_prefix='Téléphone Android : ')
bullet('rendez-vous sur www.immozone.pro depuis n\u2019importe quel navigateur '
       '(téléphone ou ordinateur). Toutes les fonctions y sont disponibles.',
       bold_prefix='Sur Internet : ')
note('L\u2019application n\u2019est pas encore disponible sur iPhone (App Store). '
     'Les utilisateurs d\u2019iPhone sont priés d\u2019utiliser la version web : '
     'ouvrez Safari, tapez www.immozone.pro — le site fonctionne exactement comme l\u2019application. '
     'Vous pouvez l\u2019ajouter à votre écran d\u2019accueil : bouton Partager → '
     '« Ajouter à l\u2019écran d\u2019accueil ».', label="📌 Utilisateurs iPhone : ")

# ───────────────────────── 2. TYPES D'UTILISATEURS ─────────────────────────
h1('2. Les types d\u2019utilisateurs')
para('ImmoZone distingue deux grands profils :', bold=True)

h2('2.1 Le VISITEUR (demandeur)')
bullet('Toute personne qui cherche un bien : maison, appartement, parcelle, etc.')
bullet('Il peut consulter toutes les annonces, filtrer par commune, type et prix, '
       'voir les photos et contacter directement l\u2019annonceur — sans créer de compte.')
bullet('C\u2019est 100 % GRATUIT pour le visiteur, sans aucune limite.')

h2('2.2 L\u2019ANNONCEUR')
para('C\u2019est celui qui publie des biens. À la création du compte, il choisit '
     'obligatoirement sa catégorie :')
bullet('professionnel structuré, avec plusieurs biens en portefeuille et une image de marque.',
       bold_prefix='🏢 Agence Immobilière : ')
bullet('intermédiaire indépendant qui met en relation propriétaires et clients.',
       bold_prefix='🤝 Commissionnaire : ')
bullet('particulier qui publie directement son propre bien, sans intermédiaire.',
       bold_prefix='🏠 Propriétaire : ')
note('La catégorie est affichée sur le profil public de l\u2019annonceur : elle inspire '
     'confiance aux visiteurs. Choisissez celle qui correspond réellement à votre activité.')

# ───────────────────────── 3. CRÉATION DE COMPTE ─────────────────────────
h1('3. Création du compte (annonceur)')
para('Étapes à suivre :', bold=True)
step('Ouvrez l\u2019application (ou www.immozone.pro) et touchez « S\u2019inscrire ».')
step('Renseignez votre nom complet (ou le nom de votre agence).')
step('Entrez votre numéro de téléphone — c\u2019est votre identifiant de connexion. '
     'Utilisez un numéro WhatsApp actif.')
step('Choisissez votre catégorie : Agence Immobilière, Commissionnaire ou Propriétaire.')
step('Créez un mot de passe solide (lettres + chiffres + symbole) et mémorisez-le.')
step('Code parrainage (facultatif) : si un agent ImmoZone ou un ami vous a donné un code, '
     'saisissez-le ici — il recevra un bonus et cela ne vous coûte rien.')
step('Validez : un code de confirmation vous est envoyé sur WhatsApp. Saisissez-le.')
step('🎁 Félicitations ! Votre compte est créé et des annonces GRATUITES '
     'vous sont offertes pour démarrer immédiatement.')
note('Pour vous connecter ensuite : numéro de téléphone + mot de passe. '
     'En cas d\u2019oubli du mot de passe, contactez le support ImmoZone sur WhatsApp.')

# ───────────────────────── 4. POSTER UNE ANNONCE ─────────────────────────
h1('4. Publier une annonce')
para('Étapes à suivre :', bold=True)
step('Connectez-vous, puis touchez le bouton « Publier » (ou « + »).')
step('Choisissez le type de transaction : Location ou Vente.')
step('Choisissez le type de bien : maison/villa, appartement, parcelle, bureau, etc.')
step('Indiquez la localisation : pays, province, commune, quartier/avenue.')
step('Renseignez le prix (en USD) et les caractéristiques : chambres, salons, superficie…')
step('Rédigez un titre clair et une description honnête '
     '(ex. : « Maison 3 chambres, parcelle clôturée, eau + forage — Lemba Salongo »).')
step('Ajoutez les PHOTOS : plusieurs photos réelles, nettes, prises en plein jour. '
     'La première photo devient la photo principale de l\u2019annonce.')
step('Choisissez la durée de publication, puis validez. '
     'Si vous avez encore des annonces gratuites, elles sont utilisées automatiquement ; '
     'sinon le coût en crédits (selon la commune et le type) est affiché avant confirmation.')
step('Votre annonce est EN LIGNE : les visiteurs peuvent la voir et vous contacter.')
note('Une annonce avec 4 photos nettes et un prix affiché reçoit beaucoup plus d\u2019appels '
     'qu\u2019une annonce sans photo. Ne publiez jamais la photo d\u2019un bien qui n\u2019est pas le vôtre.')

# ───────────────────────── 5. RECHARGER ─────────────────────────
h1('5. Recharger son compte (crédits)')
para('Les crédits servent à publier de nouvelles annonces quand les annonces gratuites '
     'sont épuisées. Le paiement se fait par Mobile Money — aucun compte bancaire n\u2019est nécessaire.')
para('Étapes à suivre :', bold=True)
step('Touchez votre photo de profil (en haut) puis « Recharger », '
     'ou le bouton « Recharger » de votre tableau de bord.')
step('Choisissez un pack de crédits (le prix en USD est affiché pour chaque pack).')
step('Choisissez votre moyen de paiement :')
bullet('le paiement est automatique : entrez votre numéro Orange Money, '
       'validez le code PIN sur votre téléphone (message USSD), et vos crédits sont '
       'ajoutés automatiquement en quelques instants.',
       bold_prefix='🟠 Orange Money : ')
bullet('effectuez le transfert vers le numéro indiqué à l\u2019écran, puis '
       'soumettez la référence de la transaction dans le formulaire. Un administrateur '
       'vérifie et valide — vos crédits sont ajoutés et vous recevez une notification.',
       bold_prefix='🔴 M-Pesa / Airtel Money : ')
step('Votre nouveau solde s\u2019affiche dans votre tableau de bord.')
note('Profitez des PROMOTIONS de recharge quand elles sont actives : des paliers bonus '
     'offrent des crédits supplémentaires selon le montant rechargé.')

# ───────────────────────── 6. GÉRER SES ANNONCES ─────────────────────────
h1('6. Gérer ses annonces (tableau de bord)')
para('Depuis « Mon tableau de bord », l\u2019annonceur voit et gère tout :')
bullet('actives, expirées, vendues/occupées — avec le nombre de VUES de chacune.',
       bold_prefix='Ses annonces : ')
bullet('corrigez le prix, la description ou les photos à tout moment.',
       bold_prefix='Modifier : ')
bullet('quand une annonce expire, renouvelez-la en un clic (coût en crédits affiché).',
       bold_prefix='Renouveler : ')
bullet('dès que le bien est loué ou vendu, marquez-le — cela protège votre sérieux '
       'auprès des clients.',
       bold_prefix='Marquer Vendu / Occupé : ')
bullet('mettez votre annonce en avant pour qu\u2019elle apparaisse en tête de liste '
       'et attire plus de visiteurs.',
       bold_prefix='Booster (option) : ')

# ───────────────────────── 7. PARRAINAGE ─────────────────────────
h1('7. Le parrainage : gagnez des crédits')
step('Ouvrez le menu profil → « Parrainage » : votre CODE personnel s\u2019affiche.')
step('Partagez ce code avec vos contacts (WhatsApp, bouche-à-oreille).')
step('Quand une personne s\u2019inscrit avec votre code ET effectue sa première recharge, '
     'vous recevez automatiquement le même nombre de crédits qu\u2019elle. ')
step('Suivez vos filleuls et vos gains directement dans l\u2019écran Parrainage.')
note('La commission est versée une seule fois par filleul (sa première recharge). '
     'Plus vous parrainez, plus vous publiez gratuitement !')

# ───────────────────────── 8. CONTACTER / ÊTRE CONTACTÉ ─────────────────────────
h1('8. Contact entre visiteurs et annonceurs')
bullet('Sur chaque annonce, le visiteur dispose de boutons de contact direct : '
       'appel, WhatsApp et messagerie interne ImmoZone.')
bullet('L\u2019annonceur reçoit une notification à chaque message — répondez vite : '
       'un client qui attend va voir ailleurs.')
bullet('Le profil public de l\u2019annonceur (photo, catégorie, ancienneté, autres annonces) '
       'est visible par les visiteurs : soignez-le.')
bullet('Chaque annonce peut être PARTAGÉE sur WhatsApp avec un aperçu (photo + titre + prix) : '
       'partagez vos propres annonces dans vos groupes, c\u2019est votre meilleure publicité.')

# ───────────────────────── 9. BONNES PRATIQUES & SÉCURITÉ ─────────────────────────
h1('9. Bonnes pratiques et sécurité')
bullet('Ne publiez que des biens RÉELS que vous êtes autorisé à proposer.')
bullet('Affichez toujours le vrai prix : les annonces sans prix ou trompeuses font fuir les clients.')
bullet('Visiteurs : ne versez JAMAIS d\u2019argent sans avoir visité le bien et vérifié les documents.')
bullet('Signalez tout comportement suspect au support ImmoZone.')
bullet('Ne partagez jamais votre mot de passe. ImmoZone ne vous le demandera jamais.')

# ───────────────────────── 10. AIDE ─────────────────────────
h1('10. Besoin d\u2019aide ?')
bullet('Support WhatsApp ImmoZone : ____________________ (numéro à compléter)')
bullet('Site web : www.immozone.pro')
bullet('Vidéo de démonstration : https://youtu.be/sbS-D2L891s')
para('')
para('ImmoZone — Ta maison, elle est là ! 🏠', bold=True, color=ACCENT,
     align=WD_ALIGN_PARAGRAPH.CENTER)

doc.save('/home/user/webapp/docs/Manuel_Utilisateur_ImmoZone.docx')
print('OK — document généré')
