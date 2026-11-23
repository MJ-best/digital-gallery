# App Store Release Kit — Digital Gallery

macOS · iPadOS App Store 배포를 위한 프로젝트 설정, 메타데이터, 개인정보 처리방침, 아카이브 절차를 정리한 문서입니다.

---

## 1. 사전 준비 체크리스트 (Apple Developer / App Store Connect)

1. **Bundle ID & Team ID 변경**
   * `apps/xcode/project.yml`의 `PRODUCT_BUNDLE_IDENTIFIER` (`com.digitalgallery.app`)를 본인의 Apple Developer 계정에 등록한 고유 Bundle ID로 변경합니다.
   * App Store Connect에서 새 앱을 등록하고 macOS / iOS(iPadOS) 플랫폼을 활성화합니다.
2. **iCloud Container 활성화**
   * Apple Developer Portal → Identifiers → 해당 Bundle ID → **iCloud (CloudKit / CloudDocuments)** 체크 후 컨테이너 `iCloud.<YOUR_BUNDLE_ID>`를 연결합니다.
3. **로컬 아카이브 & 업로드**
   ```bash
   # 1) 서명 없는 로컬 검증 아카이브
   ./scripts/archive-appstore.sh macos
   ./scripts/archive-appstore.sh ipados

   # 2) Apple Team ID로 App Store Connect 서명 및 내보내기
   ./scripts/archive-appstore.sh macos YOUR_TEAM_ID
   ./scripts/archive-appstore.sh ipados YOUR_TEAM_ID
   ```
   또는 `apps/xcode/DigitalGallery.xcodeproj`를 Xcode에서 열고 `Signing & Capabilities`에서 Team을 지정한 뒤 **Product → Archive → Distribute App → App Store Connect**로 업로드합니다.

---

## 2. App Store Connect 메타데이터 (바로 붙여넣기용)

### 한국어 (ko)
* **앱 이름 (30자 이내):** `Digital Gallery — 디지털 전시관`
* **부제 (30자 이내):** `사진 폴더를 스토리가 있는 전시로`
* **카테고리:** 사진 및 비디오 (`public.app-category.photography`)
* **키워드 (100자 이내):** `사진전시,디지털전시관,모바일청첩장,포토북,앨범,스크롤스토리,사진정리,아카이브,전시회,포토에세이`
* **설명:**
  > 사진을 단순히 저장하는 앱이 아니라, 하나의 전시 경험으로 만드는 앱.
  >
  > Digital Gallery는 폴더나 사진 보관함에 쌓여 있던 사진과 영상을 스크롤 동선, 조명 변화, 앰비언트 사운드, 캡션이 어우러진 나만의 디지털 전시관으로 만들어 줍니다.
  >
  > **주요 기능**
  > • **EXIF 자동 큐레이션**: 촬영 시간과 가로/세로 비율을 분석해 챕터와 전시 씬을 자동으로 제안합니다.
  > • **4가지 에디토리얼 디자인 시안**: 에디토리얼 매거진, 토스 미니멀, 미드나잇 필름, 아틀리에 포스터 테마를 실시간으로 전환해 보세요.
  > • **발걸음을 설계하는 스크롤 연출**: 세로 스크롤 중 가로 갤러리로 전환되는 Sticky 동선, 핀 고정 스토리, 씬별 배경 암전과 사운드 크로스페이드를 지원합니다.
  > • **서버 없는 공유**: Safari에서 바로 감상할 수 있는 단일 HTML 파일과 원본 편집이 가능한 `.gallery` 프로젝트 패키지를 내보낼 수 있습니다.
  > • **iCloud Drive 동기화**: Mac과 iPad 사이에서 `.gallery` 패키지를 안전하게 동기화합니다.
  > • **100% 온디바이스 프라이버시**: 사진과 프로젝트는 외부 서버로 전송되지 않으며, 기기와 사용자의 iCloud에만 안전하게 보관됩니다.

### English (en-US)
* **App Name:** `Digital Gallery — Photo Exhibitions`
* **Subtitle:** `Turn photo folders into interactive exhibitions`
* **Keywords:** `photo exhibition,digital gallery,storytelling,photo book,minimal,scroll,archive,curator,html,album`
* **Description:**
  > Not just another photo storage app — Digital Gallery turns your photos and videos into a curated, story-driven exhibition.
  >
  > Design the viewer's footsteps with vertical-to-horizontal scroll choreography, smooth room lighting transitions, crossfading ambient soundscapes, and museum-style captions. Export a self-contained HTML exhibition anyone can view in Safari, or keep editing across Mac and iPad with `.gallery` packages synced via iCloud Drive. 100% private and on-device.

---

## 3. App Privacy (App Store Connect 설문 & PrivacyInfo.xcprivacy)

* **Data Collection:** **No, we do not collect data from this app.**
* **Tracking:** `NSPrivacyTracking = false`
* **Required Reason API:** `NSPrivacyAccessedAPICategoryFileTimestamp` (`C617.1`) — 스캔한 사진 폴더의 EXIF 미포함 이미지 정렬을 위해 파일 수정 시각을 읽는 용도로 `apps/xcode/Resources/PrivacyInfo.xcprivacy`에 선언 완료.
* **Export Compliance:** `ITSAppUsesNonExemptEncryption = false` (`Info.plist`에 선언 완료).

---

## 4. 심사 노트 (App Review Notes)

> Digital Gallery works 100% offline on-device without requiring an account or login.
>
> To test quickly:
> 1. Launch the app and click the sparkle (**Demo**) toolbar button, or select any local folder of photos via **Scan Folder** / **Photos Library**.
> 2. Switch design presets in the right Inspector (`Editorial Magazine`, `Toss Minimal`, `Midnight Film`, `Atelier Poster`), edit scene captions inline, and adjust lighting moods to see live zero-reload updates in the preview canvas.
> 3. Use **Share / Export → Single HTML** to export a standalone HTML exhibition that opens directly in Safari.
