# Chum Bucket

Challenge your friends, bet crypto, stay accountable! 🚀

Chum Bucket is a social Web3 app on Solana where you can create fun challenges with friends, lock SOL or CHUM tokens in secure escrow, and keep each other motivated through friendly competition.

**Inspired by:** [This viral Twitter post](https://x.com/IrffanAsiff/status/1923050813615718699) that sparked the idea for crypto-powered accountability.

## ✨ Features

- **Social Challenges:** Create dares with friends using email or wallet address
- **Secure Escrow:** Lock SOL/CHUM tokens in Solana smart contracts
- **Winner Takes All:** Challenge creator decides the winner
- **Transparent Fees:** 1% fee (max $10) - 50% team, 50% community airdrops
- **Mobile-First:** Built with Flutter for iOS & Android

## 📱 Screenshots

<p align="center">
  <img src="assets/images/open_sourced_design_inspiration/irfan/img1.jpeg" alt="Chum Bucket App Design 1" height="400" />
  <img src="assets/images/open_sourced_design_inspiration/irfan/img2.jpeg" alt="Chum Bucket App Design 2" height="400" />
  <img src="assets/images/open_sourced_design_inspiration/irfan/img3.jpeg" alt="Chum Bucket App Design 3" height="400" />
</p>

## 🔧 Tech Stack

- **Frontend:** Flutter (iOS/Android)
- **Backend:** Supabase + Privy Auth
- **Blockchain:** Solana + Anchor (Rust)
- **Database:** Supabase PostgreSQL

## 🚀 Getting Started

1. **Clone & Install:**
```bash
git clone https://github.com/Immadominion/Chum-Bucket.git
cd Chum-Bucket/chumbucket
flutter pub get
```

2. **Setup Environment:**
   - Add Supabase credentials to `.env`
   - Configure Privy authentication
   - Deploy Anchor smart contract

3. **Run:**
```bash
flutter run
```

## 🏗️ Architecture

- **Smart Contract:** Secure escrow with program-derived addresses (PDAs)
- **Fee Structure:** Transparent 1% fee (capped at $10) sent to public wallet
- **Auth Flow:** Privy Google OAuth synced with Supabase
- **Real-time Updates:** Live challenge status via Supabase

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

## 📞 Contact

**Built by:** [@Heisjoel0x](https://twitter.com/Heisjoel0x)  
**Email:** immadominion@gmail.com

---

*Going production-beta soon! 🎉*
