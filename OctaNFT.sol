// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
// import "@openzeppelin/contracts/access/AccessControl.sol";

interface IOctaNFTFactory {
    function owner() external view returns (address);
    function auction() external view returns (address);
    function marketplace() external view returns (address);
    function feeRecipient() external view returns (address);
    function mintFee() external view returns (uint256);
    function octaToken() external view returns (address);
    function hasRole(bytes32 role, address _admin) external view returns (bool);
}

contract OctaNFT is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable, ReentrancyGuard, EIP712 {
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;
    using Strings for uint256;
    using ECDSA for bytes32;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    Counters.Counter private _tokenIds;

    bool public isInitialized;
    string private _nameExtended;
    string private _symbolExtended;

    /// @notice Octa Factory address
    IOctaNFTFactory public octaFactory;

    mapping(uint256 => bool) public isNonceUsed;

    // @notice Represents an un-minted NFT, which has not yet been recorded into the blockchain. A signed voucher can be redeemed for a real NFT using the redeem function.
    struct NFTVoucher {
        // @notice The id of the token to be redeemed. Must be unique - if another token with this ID already exists, the redeem function will revert.
        uint256 tokenId;

        // @notice The minimum price (in wei) that the NFT creator is willing to accept for the initial sale of this NFT.
        uint256 minPrice;

        // @notice The metadata URI to associate with this token.
        string uri;

        // @notice The original creator of this token.
        address creator;

        // @notice unique nonce
        uint256 nonce;

        // @notice the EIP-712 signature of all other fields in the NFTVoucher struct. For a voucher to be valid, it must be signed by an account with the MINTER_ROLE.
        bytes signature;
    }

    /// @dev Events of the contract
    event Minted(
        uint256 tokenId,
        address beneficiary,
        string tokenUri,
        address minter
    );

    /// @notice Contract constructor
    constructor(
    ) ERC721("", "") EIP712("OctaNFTCollections", "1") ReentrancyGuard() {
        // octaFactory = IOctaNFTFactory(msg.sender);
        // _setupRole(MINTER_ROLE, _admin);
    }

    function initialize(string memory _name, string memory _symbol) external onlyOwner{
        require(!isInitialized, "Already initialized");
        isInitialized = true;

        octaFactory = IOctaNFTFactory(msg.sender);

        _nameExtended = _name;
        _symbolExtended = _symbol;
    }

    function name() public view override returns (string memory) {
        return _nameExtended;
    }

    function symbol() public view override returns (string memory) {
        return _symbolExtended;
    }

     // TODO check only owner can call
    // function mint(address _to, string calldata _tokenUri) external payable {
    //     require(msg.value >= octaFactory.platformFee(), "Insufficient funds to mint.");
    //     _tokenIds.increment();
    //     uint256 newTokenId = _tokenIds.current();

    //     _safeMint(_to, newTokenId);
    //     _setTokenURI(newTokenId, _tokenUri);

    //     // Send OCTA fee to fee recipient
    //     (bool success, ) = octaFactory.feeRecipient().call{value: msg.value}("");
    //     require(success, "Transfer failed");

    //     emit Minted(newTokenId, _to, _tokenUri, _msgSender());
    // }
    
    function buy(NFTVoucher calldata voucher) external payable {
        require(!isNonceUsed[voucher.nonce], "NFT: nonce is used");
        address signer = _verify(voucher);
        require(octaFactory.hasRole(MINTER_ROLE, signer), "Signature invalid or unauthorized");
        // require(hasRole(MINTER_ROLE, signer), "Signature invalid or unauthorized");
        uint mintFeeAmount = (octaFactory.mintFee() * voucher.minPrice) / 10000; 
        
        if (octaFactory.octaToken() == address(0)) {
            require(msg.value >= voucher.minPrice, "Insufficient funds to redeem");
            uint creatorFee = msg.value - mintFeeAmount;
            payable(owner()).transfer(creatorFee);
            payable(octaFactory.feeRecipient()).transfer(mintFeeAmount);
        } else {
            // require(acceptedTokens[octaFactory.octaToken()], "Token not accepted");
            uint creatorFee = (voucher.minPrice) - mintFeeAmount;
            IERC20(octaFactory.octaToken()).safeTransferFrom(msg.sender, owner(), creatorFee);
            IERC20(octaFactory.octaToken()).safeTransferFrom(msg.sender, octaFactory.feeRecipient(), mintFeeAmount);
        }
        isNonceUsed[voucher.nonce] = true;
        _mint(owner(), voucher.tokenId);
        _setTokenURI(voucher.tokenId, voucher.uri);
        _safeTransfer(owner(), msg.sender, voucher.tokenId, "");
    }

    // function updateMinterRole() external {
    //     _setupRole(MINTER_ROLE, octaFactory.owner());   
    // }

    /**
    @notice Burns a DigitalaxGarmentNFT, releasing any composed 1155 tokens held by the token itself
    @dev Only the owner or an approved sender can call this method
    @param _tokenId the token ID to burn
    */
    // TODO to be decided to implement
    function burn(uint256 _tokenId) external {
        address operator = _msgSender();
        require(
            ownerOf(_tokenId) == operator || isApproved(_tokenId, operator),
            "Only garment owner or approved"
        );

        // Destroy token mappings
        _burn(_tokenId);
    }

    /**
     * @dev checks the given token ID is approved either for all or the single token ID
     */
    function isApproved(uint256 _tokenId, address _operator)
        public
        view
        returns (bool)
    {
        return
            isApprovedForAll(ownerOf(_tokenId), _operator) ||
            getApproved(_tokenId) == _operator;
    }

    /**
     * Override isApprovedForAll to whitelist Octa contracts to enable gas-less listings.
     */
    function isApprovedForAll(address owner, address operator)
        public
        view
        override
        returns (bool)
    {
        // Whitelist Octa auction, marketplace contracts for easy trading.
        if (octaFactory.auction() == operator || octaFactory.marketplace() == operator) {
            return true;
        }

        return super.isApprovedForAll(owner, operator);
    }

    /**
     * Override _isApprovedOrOwner to whitelist Octa contracts to enable gas-less listings.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId)
        internal
        view
        override
        returns (bool)
    {
        require(
            _exists(tokenId),
            "ERC721: operator query for nonexistent token"
        );
        address owner = ERC721.ownerOf(tokenId);
        if (isApprovedForAll(owner, spender)) return true;
        return super._isApprovedOrOwner(spender, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function _hash(NFTVoucher calldata voucher) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            keccak256("NFTVoucher(uint256 tokenId,uint256 minPrice,string uri,address creator,uint256 nonce)"),
            voucher.tokenId,
            voucher.minPrice,
            keccak256(bytes(voucher.uri)),
            voucher.creator,
            voucher.nonce
        )));
    }

    function _verify(NFTVoucher calldata voucher) internal view returns (address) {
        bytes32 digest = _hash(voucher);
        return ECDSA.recover(digest, voucher.signature);
    }

    function getChainID() external view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override (ERC721, ERC721Enumerable) returns (bool) {
        return ERC721.supportsInterface(interfaceId);
    }

}
