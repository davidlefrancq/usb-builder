# Phase 1 — Recherche documentaire (2026-11-15)

Statut : recherche **documentaire uniquement**. Tout reste à confirmer en phase 2 (Hyper-V, Secure Boot actif).
Légende : **[DOC]** source officielle ou code source ; **[INF]** déduction ou source communautaire.

## Points techniques

### 1. Chainloading Secure Boot depuis le GRUB signé d'Ubuntu
- Faisable. GRUB (module `peimage`) délègue la vérification à shim : firmware `db` + MokList + certificat Canonical, après `dbx`. [DOC]
  - https://salsa.debian.org/grub-team/grub/-/raw/master/debian/patches/secure-boot/efi-peimage.patch
  - https://bugs.launchpad.net/ubuntu/+source/grub2/+bug/1847458
- `bootmgfw.efi` de Windows : accepté via `db`. L'absence de section `.sbat` est tolérée sur le chemin du protocole shim. [DOC]
  - https://raw.githubusercontent.com/rhboot/shim/main/pe.c
- `shimx64.efi` d'une autre distribution : accepté via le Microsoft UEFI CA. shim gère le cas « shim chargé par un shim ». [DOC]
  - https://raw.githubusercontent.com/rhboot/shim/main/shim.c
- **Règle** : chainloader le **shim** de la cible, jamais son `grubx64.efi`. Le GRUB de Debian est signé par la clé Debian, qu'Ubuntu ne reconnaît pas. [INF, confiance haute]
- **Règle** : dans chaque entrée, `search --fs-uuid --set=root <uuid>` **avant** `chainloader`. Sinon : erreur « malformed device path » (LP#2130774). En dernier recours : `rmmod peimage` (LP#2030810).

### 2. Où le GRUB signé d'Ubuntu cherche `grub.cfg`
- Image « disque » `grubx64.efi` (paquet `grub-efi-amd64-signed`) : prefix `/EFI/ubuntu`, sur la partition d'où GRUB a été chargé. [DOC]
  - https://git.launchpad.net/ubuntu/+source/grub2/plain/debian/build-efi-images
- **Choix** : `P1:/EFI/BOOT/BOOTX64.EFI` = shim Ubuntu, `P1:/EFI/BOOT/grubx64.efi` = GRUB « disque », `P1:/EFI/ubuntu/grub.cfg` = notre menu.
- À éviter :
  - `gcdx64.efi` (GRUB de l'ISO) : il cherche `/.disk/info` et tomberait sur P3 ;
  - `fbx64.efi` dans `/EFI/BOOT` : shim lancerait le fallback au lieu de GRUB.
- Modules intégrés (noble) : `part_gpt`, `fat`, `ext2`, `iso9660`, `chain`, `peimage`, `search*`, `configfile`… `ntfs` absent des versions récentes.
- Le GRUB signé d'Ubuntu 26.10 est allégé. **Prendre le GRUB signé d'une LTS** (24.04.x ou 26.04). [DOC]

### 3. Ubuntu live (casper) sur une partition autre que la première
- casper parcourt **toutes** les partitions et cherche `/casper/*.squashfs`. La position de la partition n'a pas d'importance. [DOC]
  - https://git.launchpad.net/ubuntu/+source/casper/plain/scripts/casper
- Le contrôle UUID est validé si `.disk/` est copié intact. Sinon : `ignore_uuid`.
- Systèmes de fichiers acceptés : `vfat`, `ext4`, `ntfs`… mais pas `exFAT`. [DOC]
- FAT32 probablement suffisant : plusieurs squashfs, chacun sous 4 Go. **À vérifier en phase 2** avec l'ISO réel. [INF]
- Une fois chainloadé, le GRUB de l'ISO prend P3 comme `$root` (prefix `/boot/grub` sur son propre périphérique). [INF]

### 4. Clonezilla
- `live-boot` parcourt tous les périphériques et cherche `/live`. La méthode officielle est une partition FAT32 qui contient le zip extrait, **`.disk` compris**. [DOC]
  - https://clonezilla.org/liveusb.php
  - https://manpages.debian.org/trixie/live-boot-doc/live-boot.7.en.html
- Son `grub.cfg` fait `search --set -f /live/vmlinuz`. Seule P4 contient `/live`. [DOC]
- La version stable utilise le shim signé Microsoft de Debian. Des échecs SBAT sont signalés selon les builds. **Le choix stable ou alternative se fera sur test.** [INF]

### 5. `bootmgr` de Windows depuis P2
- `[boot]` désigne la partition d'où `bootmgr` a été chargé : `BCD` et `boot.wim` sont donc lus sur P2, à condition que `$root` soit bien positionné. [INF]
- Les fichiers `.swm` vont dans `\sources`. `autounattend.xml` va à la racine de P2, et **sur aucune autre partition**. [DOC]
  - https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-automation-overview
- Sur un build 24H2, des fichiers Windows répartis sur deux partitions ont échoué. Tous les fichiers sur une seule partition FAT32 a fonctionné. C'est notre cas. [INF]

### 6. SBAT, dbx et certificats 2023

| Certificat | Validité |
|---|---|
| Microsoft UEFI CA 2011 | expiré le 2026-06-27 |
| Windows Production PCA 2011 | expiré le 2026-10-19 |
| Windows UEFI CA 2023 | jusqu'en 2035 |
| Microsoft UEFI CA 2023 | jusqu'en 2038 |

Source : https://wiki.debian.org/SecureBoot/CAChanges

- Le firmware n'applique pas les dates d'expiration. Les binaires déjà signés continuent de démarrer. [DOC]
- **Ubuntu** : les médias jusqu'à 26.04 GA sont signés 2011. Les mises à jour de shim publiées après juin 2026 sont signées 2023 uniquement. [DOC]
  - https://discourse.ubuntu.com/t/microsoft-uefi-ca-rotation-what-it-means-for-ubuntu-users-and-vendors/82652
- **Debian** : shim 16.1-2 est signé 2011 **et** 2023. Le prochain sera signé 2023 uniquement. [DOC]
- **Windows** : les médias contiennent les deux `bootmgr`. Le défaut est encore 2011 et passera à 2023. [DOC]
  - https://support.microsoft.com/help/5132953
  - https://support.microsoft.com/help/5025885
- **Conséquence** : un binaire signé 2023 uniquement ne démarre pas sur un firmware ancien sans les certificats 2023. Un binaire signé 2011 ne démarre pas si la machine a révoqué PCA 2011. → `Verify` doit afficher l'autorité de chaque chargeur.
- Niveau SBAT le plus récent (2026-10-26) : `shim,4`, `grub,7`. Un ISO ancien peut être refusé par son propre shim. → toujours prendre les ISO récents. [DOC]
  - https://raw.githubusercontent.com/rhboot/shim/main/SbatLevel_Variable.txt
- **Hyper-V** : le modèle « Microsoft Windows » refuse shim, donc toute la clé est refusée (attendu). Le modèle « Microsoft UEFI Certificate Authority » est le bon. **Vérifier le contenu de `db` dans la VM** : les certificats 2023 n'y sont pas garantis.

### 7. Clé USB amovible à plusieurs partitions
- Prise en charge depuis Windows 10 1703. [DOC]
- Firmware (EDK2) : il essaie `\EFI\BOOT\BOOTX64.EFI` sur **chaque** partition FAT, dans l'ordre des partitions. P1 passe en premier. [DOC EDK2, INF autres firmwares]
- → Marquer seulement P1 comme ESP. Tester sur du vrai matériel.

## autounattend.xml — faisabilité (Windows 11 25H2, build 26200)

| Ligne | Faisable | Écart |
|---|---|---|
| fr-FR / AZERTY / Romance Standard Time | Oui | — |
| Windows 11 Pro, sans clé | Avec contournement | Clé **générique d'installation** Pro (`VK7JG-…`), qui n'active rien. L'activation vient de la licence numérique ou OEM. Sans aucune clé, Setup affiche le choix d'édition. |
| Compte local `admin`, sans compte Microsoft | Oui, aujourd'hui | `LocalAccounts` + `HideOnlineAccountScreens`. Microsoft retire les autres contournements dans les builds Insider : risque pour l'avenir. |
| Mot de passe demandé au 1er démarrage | **Pas en natif** | Option A : OOBE demande le compte, mais le nom `admin` n'est pas imposé. Option B : `admin` sans mot de passe, changement forcé à la connexion suivante. |
| Confidentialité tout désactivé | Partiel | `ProtectYourPC=3` désactive pub, localisation et expériences personnalisées. **Télémétrie : minimum « Requis » sur Pro**, impossible de la couper totalement. |
| Disque manuel | Oui | Ni `DiskConfiguration` ni `ImageInstall`. |
| Pas de contournement TPM/CPU | Oui | — |

### Décisions

- **Mot de passe → option B** (2026-11-15) : compte `admin` créé sans mot de passe. Une `FirstLogonCommand` exécute `net user admin /logonpasswordchg:yes` puis ferme la session, et Windows exige un mot de passe à la connexion suivante. Ne pas activer « mot de passe sans expiration » sur ce compte.
- **Télémétrie → minimum « Requis »** (2026-11-15) : `AllowTelemetry=1` + `ProtectYourPC=3`. La publicité, la localisation et les expériences personnalisées sont désactivées.
- **Clé produit → clé générique d'installation Pro** (2026-11-15) : `VK7JG-NPHTM-C97JM-9MPGT-3V66T` (publique, aucune activation), `WillShowUI=OnError`. L'activation passe par la licence numérique ou OEM.

Sources :
- https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-setup-userdata-productkey-key
- https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-protectyourpc
- https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-system#allowtelemetry
- https://blogs.windows.com/windows-insider/?p=178291
