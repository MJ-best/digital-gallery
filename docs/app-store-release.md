# App Store Release Kit — Memoria

macOS · iOS / iPadOS App Store 배포를 위한 프로젝트 설정, 메타데이터, 개인정보 처리방침, 아카이브 절차를 정리한 문서입니다.

---

## 1. 사전 준비 체크리스트 (Apple Developer / App Store Connect)

1. **Bundle ID & Team ID 확인**
   * `apps/xcode/project.yml`에 `PRODUCT_NAME: Memoria`, `PRODUCT_BUNDLE_IDENTIFIER: com.mjbest.digitalgallery`가 설정되어 있습니다.
   * App Store Connect에서 iOS(iPhone/iPad) 및 macOS 플랫폼 모두 등록되어 있습니다.
2. **업로드용 스크린샷 위치 (드래그 앤 드롭 규격 완료)**
   * **iPhone 6.7" (`1290×2796`):** `apps/xcode/AppStoreScreenshots/iOS/` (`01_iPhone_Cover.png` ~ `03_iPhone_Travel.png`)
   * **macOS (`2880×1800`):** `apps/xcode/AppStoreScreenshots/macOS/` (`01_Memoria_Main.png` ~ `03_Travel_Exhibition.png`)
3. **App Store Connect 직접 업로드 명령**
   ```bash
   xcodebuild -exportArchive \
     -archivePath build/archives/DigitalGallery-iPadOS.xcarchive \
     -exportPath build/upload/ipados \
     -exportOptionsPlist apps/xcode/ExportOptions.plist \
     -allowProvisioningUpdates
   ```

---

## 2. App Store Connect 메타데이터 (바로 붙여넣기용)

### 한국어 (ko)
* **앱 이름 (30자 이내):** `Memoria` *(이미 사용 중일 경우 `Memoria — 디지털 전시관`)*
* **부제 (30자 이내):** `소중한 순간을 나만의 디지털 전시로`
* **프로모션 텍스트 (170자 이내):**
  > 사진 폴더와 앨범을 스크롤 스토리, 조명 전환, 캡션이 어우러진 나만의 디지털 전시관과 모바일 청첩장으로 만들어 보세요. 서버 없이 단일 HTML로 바로 공유할 수 있습니다.
* **카테고리:**
  * 기본 카테고리: `사진 및 비디오` (`Photo & Video`)
  * 보조 카테고리(선택): `라이프스타일` (`Lifestyle`)
* **키워드 (100자 이내):**
  `메모리아,사진전시,디지털전시관,모바일청첩장,포토북,웨딩앨범,스크롤스토리,사진정리,여행기록,포토에세이`
* **설명:**
  > 사진을 단순히 저장하는 앱이 아니라, 하나의 전시 경험으로 만드는 앱 — Memoria.
  >
  > Memoria는 사진 보관함과 폴더에 쌓여 있던 소중한 순간들을 스크롤 동선, 조명 변화, 앰비언트 사운드, 캡션이 어우러진 나만의 디지털 전시관으로 만들어 줍니다. 여행 기록, 포토 에세이, 모바일 청첩장까지 누구나 몇 분 만에 완성할 수 있습니다.
  >
  > **주요 기능**
  > • **EXIF 자동 큐레이션**: 촬영 시간과 사진 비율을 분석해 챕터와 전시 씬을 자동으로 구성해 줍니다.
  > • **5가지 감성 테마 프리셋**: Memoria 파스텔 블루, 토스 미니멀, 에디토리얼 매거진, 미드나잇 필름, 아틀리에 포스터 테마를 클릭 한 번으로 실시간 전환해 보세요.
  > • **발걸음을 설계하는 스크롤 연출**: 세로 스크롤 중 가로 갤러리로 전환되는 동선, 핀 고정 스토리, 씬별 배경 암전과 사운드 크로스페이드를 지원합니다.
  > • **서버 없는 공유 (단일 HTML 내보내기)**: 별도 서버나 가입 없이, Safari와 카카오톡 등에서 바로 열어 감상할 수 있는 단일 HTML 전시 파일로 내보내고 공유할 수 있습니다.
  > • **100% 온디바이스 프라이버시**: 계정 가입이나 외부 서버 전송 없이, 모든 사진과 `.gallery` 프로젝트는 사용자의 기기에만 안전하게 보관됩니다.
* **지원 URL:** `https://github.com/MJ-best/digital-gallery/issues`
* **마케팅 URL (선택):** `https://github.com/MJ-best/digital-gallery`
* **개인정보 처리방침 URL:** `https://github.com/MJ-best/digital-gallery/blob/main/PRIVACY.md`
* **저작권:** `© 2026 Minjun Kim`

### English (en-US)
* **App Name:** `Memoria` *(or `Memoria — Digital Gallery`)*
* **Subtitle:** `Turn photos into interactive exhibitions`
* **Promotional Text:**
  > Turn your photo folders into serene, story-driven digital exhibitions and mobile invitations—with scroll choreography, lighting transitions, and one-tap single HTML sharing.
* **Keywords:** `photo exhibition,digital gallery,wedding invitation,photo book,minimal,scroll story,album,html,archive`
* **Description:**
  > Not just another photo storage app — Memoria turns your photos and videos into a curated, story-driven digital exhibition.
  >
  > Design the viewer's footsteps with vertical-to-horizontal scroll choreography, smooth room lighting transitions, crossfading ambient soundscapes, and museum-style captions. Switch between 5 curated design presets (Memoria Pastel, Toss Minimal, Editorial Magazine, Midnight Film, Atelier Poster) in real time, and export a self-contained single HTML file anyone can open directly in Safari—with zero servers and 100% on-device privacy.

---

## 3. App Privacy & 연령 등급 (App Store Connect 설문)

* **앱 개인정보 보호 (App Privacy):**
  * **데이터 수집 여부:** **아니요, 이 앱에서는 데이터를 수집하지 않습니다. (No, we do not collect data from this app.)**
  * **추적 (Tracking):** `NSPrivacyTracking = false`
  * **Required Reason API:** `NSPrivacyAccessedAPICategoryFileTimestamp` (`C617.1`) — `apps/xcode/Resources/PrivacyInfo.xcprivacy`에 선언 완료.
* **수출 규정 준수 (Export Compliance):**
  * `ITSAppUsesNonExemptEncryption = false` (`Info.plist`에 선언 완료).
* **연령 등급 (Age Rating):**
  * 모든 항목 **없음 (None)** 선택 → **4+**
* **가격 및 사용 가능 여부:**
  * 무료 (`Free`) 또는 원하는 가격 티어 선택.

---

## 4. 심사 노트 (App Review Information → Notes)

* **로그인 필요 여부:** 체크 해제 (**Sign-in required: OFF** — 계정 없이 오프라인 동작)
* **심사 메모 (Notes):**
  > Memoria works 100% offline on-device without requiring an account or login.
  >
  > To test quickly:
  > 1. Launch the app and open one of the bundled sample exhibitions (e.g., Wedding or Travel) or tap the **Demo** toolbar button, or import photos via **Photos Library** / **Scan Folder**.
  > 2. Switch between the 5 design presets (`Memoria Pastel`, `Toss Minimal`, `Editorial Magazine`, `Midnight Film`, `Atelier Poster`), edit scene titles/captions inline, and adjust lighting moods to see live zero-reload updates in the exhibition canvas.
  > 3. Use **Share / Export → Single HTML** to generate a standalone HTML exhibition that opens directly in Safari.
