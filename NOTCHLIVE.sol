// SPDX-License-Identifier: MIT
// NOTCHLIVE — Notchlings, small pixel creatures living in a phone notch.
// Locked spec (2026-10-31):
// - Total supply: 11,111, ONE pool, NO free/paid split, NO treasury address.
// - Free mint: NFT free, 0.0001 BNB fee per mint. Paid mint: 0.001 BNB per NFT.
// - Both mintFree and mintPaid draw a RANDOM unminted token from the same pool.
// - Web gallery stays at 40 samples; minted tokens are random, not gallery order.
// - Mint is CLOSED on deploy. It only opens when the OWNER wallet signs
//   setMintEnabled(true). Deploying also makes the deployer the owner,
//   so deploy itself must be signed by the owner wallet.
// - No treasury: proceeds stay in the contract until the owner calls withdraw().
// Randomness note: this uses block data as a pseudo-random source, which is
// fine for art allocation but is NOT secure randomness against a miner/validator.
// For a high-value drop, replace _drawRandom() with Chainlink VRF before mainnet.
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NOTCHLIVE is ERC721, Ownable {
    uint256 public constant MAX_SUPPLY = 11111;
    uint256 public constant FREE_FEE = 0.0001 ether; // 0.0001 BNB per free mint
    uint256 public constant PAID_PRICE = 0.001 ether; // 0.001 BNB per paid mint
    uint256 public constant MAX_PER_TX = 10;

    uint256 public totalMinted;
    bool public mintEnabled; // false on deploy — owner must sign to open mint
    string private _baseTokenURI; // IPFS baseURI, e.g. ipfs://<CID>/ — set by owner after IPFS upload

    // Swap-and-pop random pool: no 11,111-item array is created on deploy,
    // so deploy gas stays reasonable. _available[i] == 0 means token i+1.
    mapping(uint256 => uint256) private _available;

    event MintEnabledChanged(bool enabled);
    event BaseURIChanged(string baseURI);

    constructor() ERC721("NOTCHLIVE", "NOTCH") Ownable(msg.sender) {
        mintEnabled = false;
    }

    function _drawRandom() internal returns (uint256) {
        uint256 remaining = MAX_SUPPLY - totalMinted;
        require(remaining > 0, "Sold out");
        uint256 randIndex = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    msg.sender,
                    totalMinted
                )
            )
        ) % remaining;
        uint256 tokenId = _available[randIndex] == 0
            ? randIndex + 1
            : _available[randIndex];
        uint256 lastIndex = remaining - 1;
        uint256 lastToken = _available[lastIndex] == 0
            ? lastIndex + 1
            : _available[lastIndex];
        _available[randIndex] = lastToken;
        totalMinted += 1;
        return tokenId;
    }

    function _mintRandom(uint256 amount) internal {
        for (uint256 i = 0; i < amount; i++) {
            _safeMint(msg.sender, _drawRandom());
        }
    }

    // Free mint: NFT itself is free, only the 0.0001 BNB fee is paid.
    function mintFree(uint256 amount) external payable {
        require(mintEnabled, "Mint not open yet");
        require(amount >= 1 && amount <= MAX_PER_TX, "Amount 1-10");
        require(totalMinted + amount <= MAX_SUPPLY, "Exceeds supply");
        require(msg.value == amount * FREE_FEE, "Wrong free fee");
        _mintRandom(amount);
    }

    // Paid mint: 0.001 BNB per NFT.
    function mintPaid(uint256 amount) external payable {
        require(mintEnabled, "Mint not open yet");
        require(amount >= 1 && amount <= MAX_PER_TX, "Amount 1-10");
        require(totalMinted + amount <= MAX_SUPPLY, "Exceeds supply");
        require(msg.value == amount * PAID_PRICE, "Wrong paid price");
        _mintRandom(amount);
    }

    // OWNER ONLY, must be signed by the owner wallet.
    // This is the step that opens mint — nothing mints before this signature.
    function setMintEnabled(bool enabled) external onlyOwner {
        mintEnabled = enabled;
        emit MintEnabledChanged(enabled);
    }

    // OWNER ONLY: set after IPFS upload, e.g. ipfs://<CID>/
    function setBaseURI(string calldata baseURI_) external onlyOwner {
        _baseTokenURI = baseURI_;
        emit BaseURIChanged(baseURI_);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return string(abi.encodePacked(_baseURI(), _toString(tokenId), ".json"));
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // OWNER ONLY, no treasury address: proceeds go to the owner on withdraw.
    function withdraw() external onlyOwner {
        (bool ok, ) = payable(owner()).call{value: address(this).balance}("");
        require(ok, "Withdraw failed");
    }
}
