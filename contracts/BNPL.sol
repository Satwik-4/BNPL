// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./PauserRole.sol";
import "./Roles.sol";
import "./BNPLAdmin.sol";

contract BNPL is BNPLAdmin, ERC721{

    using SafeMath for uint256;

    //address[] availableERC721;
    mapping (address => address) ERC721ToOwner; //A mapping from an NFT to it's owner.
    mapping (address => uint256) ERC721ToTokenId; //A mapping from an NFT to it's token Id.
    mapping (address => uint256) ERC721ToPrice; //A mapping from an NFT to it's price
    mapping (address => bool) ERC721IsAvailable; //A mapping from an NFT to whether is it available or not.

    struct DealVariables{

        uint256 ID; // A unique identifier for a particular deal
        uint256 onspotAmount; // The amount to be paid to get the receipt.
        uint256 price; // The total price of an NFT.
        uint256 nftTokenId; // The token Id of an NFT.
        uint256 startTime; // The block.timestamp when the loan first began (measured in seconds).
        uint256 duration; // The amount of time (measured in seconds) that can elapse before the owner can liquidate. 
        uint256 interestRateInBasisPoints; // This is the interest rate (measured in basis points, which is hundreths of a percent
        address NFTAddress; // The address of an NFT.
        address ERC20Denomination; // The ERC20 contract of the currency being used.
        address buyer; // The address of the buyer.
        

    }

    //This event is fired whenever a buyer begins a deal by calling BNPL.beginDeal().
    event buying( 
        uint256 ID,
        address buyer,
        address owner,
        uint256 onspotAmount,
        uint256 price,
        uint256 nftTokenId,
        uint256 startTime,
        uint256 duration,
        uint256 interestRateInBasisPoints,
        address NFTAddress,
        address ERC20Denomination
    );

    // This event is fired whenever a buyer successfully pays the remaining amount.
    event fullyDone(
        uint256 ID,
        address buyer,
        address owner,
        uint256 onspotAmount,
        uint256 nftTokenId,
        uint256 totalAmountPaid,
        address NFTAddress,
        address ERC20Denomination
    );

    // This event is fired whenever a owner liquidates a deal has exceeded its duration.
    event liquidated(
        uint256 ID,
        address buyer,
        address owner,
        uint256 onspotAmount,
        uint256 nftTokenId,
        uint256 maturityDate,
        uint256 liquidationDate,
        address NFTAddress
    );

    /*event note(
        address _note
    ); */

    uint256 public totalDeals = 0;
    uint256 public totalActiveDeals = 0;
    mapping (uint256 => DealVariables) public IdToDeal;
    mapping (uint256 => bool) public paidFullyOrLiquidated;

    constructor() ERC721("BNPL Promissory Note", "BNPL"){}


    
    function beginDeal(
        //uint256 _onspotAmount,
        //uint256 _price,
        //uint256 _nftTokenId,
        uint256 _duration,
        //uint256 _interestRateInBasisPoints,
        address _ERC721,
        address _ERC20Denomination
        //address _owner
    ) public {

        DealVariables memory deal = DealVariables({

            ID: totalDeals,
            onspotAmount: ERC721ToPrice[_ERC721]*3600,//_onspotAmount,
            price: ERC721ToPrice[_ERC721],//_price,
            nftTokenId: ERC721ToTokenId[_ERC721],//_nftTokenId,
            startTime: block.timestamp,
            duration: uint256(_duration),
            interestRateInBasisPoints: interest,//_interestRateInBasisPoints,
            NFTAddress: _ERC721,
            ERC20Denomination: _ERC20Denomination,
            buyer: msg.sender 

        });

        require(ERC721IsAvailable[deal.NFTAddress], "This NFT is not available on our platform");
        require(deal.duration <= maxDuration, " duration exceeds maximum loan duration");
        require(deal.duration != 0, "Duration can't be zero!!!!");
        require(deal.interestRateInBasisPoints == interest);
        require(ERC20IsAccepted[deal.ERC20Denomination], "Currency denomination is not valid");
        
        IdToDeal[totalDeals] = deal;
        totalDeals = totalDeals.add(1);
        totalActiveDeals = totalActiveDeals.add(1);

        IERC20(deal.ERC20Denomination).transferFrom(msg.sender, (ERC721ToOwner[deal.NFTAddress]), deal.onspotAmount);
        //require(tx, "Transaction failed!!!!");

        
        _mint(msg.sender, deal.ID);
        ERC721IsAvailable[deal.NFTAddress] = false;

        emit buying(
        deal.ID, 
        msg.sender, 
        ERC721ToOwner[deal.NFTAddress], 
        deal.onspotAmount, 
        deal.price, 
        deal.nftTokenId, 
        deal.startTime, 
        deal.duration, 
        deal.interestRateInBasisPoints, 
        deal.NFTAddress, 
        deal.ERC20Denomination);

}


    function OwnerEnters(address _nftAddress, uint256 _tokenId, uint256 _price) public {

        IERC721(_nftAddress).transferFrom(msg.sender, address(this), _tokenId);
        ERC721ToOwner[_nftAddress] = msg.sender;
        ERC721ToTokenId[_nftAddress] = _tokenId;
        ERC721ToPrice[_nftAddress] = _price;
        ERC721IsAvailable[_nftAddress] = true;

    }

    function OwnerWithdraws(address _nftAddress) public {

        require(msg.sender == ERC721ToOwner[_nftAddress]);
        require(ERC721IsAvailable[_nftAddress] == true);
        //IERC721(_nftAddress).transferFrom(address(this), msg.sender, ERC721ToTokenId[_nftAddress]);
        require(_transferNFTToAddress(_nftAddress, ERC721ToTokenId[_nftAddress], msg.sender),"NFT transaction failed!!!!");
        ERC721IsAvailable[_nftAddress] = false;
        delete ERC721ToTokenId[_nftAddress];
        delete ERC721ToPrice[_nftAddress];

    }

    function payTheRest(uint256 _Id) public {

        require(!paidFullyOrLiquidated[_Id], "You have already paid the full price or you have been liquidated");

        DealVariables memory deal = IdToDeal[_Id];

        require(msg.sender == deal.buyer, "Only the original buyer can continue the deal");

        address buyer = ownerOf(_Id);

        IERC20(deal.ERC20Denomination).transferFrom(msg.sender, ERC721ToOwner[deal.NFTAddress], deal.price*6400);
        IERC20(deal.ERC20Denomination).transferFrom(msg.sender, address(this), (deal.price)*6400);
        
        require(_transferNFTToAddress(deal.NFTAddress, deal.nftTokenId, deal.buyer), "NFT transaction failed!!!!");

        paidFullyOrLiquidated[_Id] = true;
        _burn(_Id);

        emit fullyDone(
        _Id, 
        deal.buyer, 
        ERC721ToOwner[deal.NFTAddress], 
        deal.onspotAmount, 
        deal.nftTokenId, 
        deal.price + ((deal.price)*(deal.interestRateInBasisPoints)), 
        deal.NFTAddress, 
        deal.ERC20Denomination);

        delete IdToDeal[_Id];

    }

    function liquidate(uint256 _Id) public {

        require(!paidFullyOrLiquidated[_Id], "You have already paid the full price or you have been liquidated");
        
        DealVariables memory deal = IdToDeal[_Id];
        uint256 maturityDate = (uint256(deal.startTime)).add(uint256(deal.duration));
        require(block.timestamp > maturityDate, "It's not overdue yet!!!!");
        address buyer = ownerOf(_Id);

        require(_transferNFTToAddress(deal.NFTAddress, deal.nftTokenId, ERC721ToOwner[deal.NFTAddress]),"NFT transaction failed!!!!");

        paidFullyOrLiquidated[_Id] = true;
        _burn(_Id);

        emit liquidated(_Id, 
        deal.buyer, 
        ERC721ToOwner[deal.NFTAddress], 
        deal.onspotAmount, 
        deal.nftTokenId, 
        maturityDate, 
        block.timestamp, 
        deal.NFTAddress
        );

        delete IdToDeal[_Id];



    }

    function _transferNFTToAddress(address _NFTAddress, uint256 _tokenId, address _recipient) internal returns (bool) {

        bool transferFromSucceeded = _attemptTransferFrom(_NFTAddress, _tokenId, _recipient);
            if(transferFromSucceeded){
                return true;
            } 
            /*else {
                bool transferSucceeded = _attemptTransfer(_NFTAddress, _tokenId, _recipient);
                return transferSucceeded;
            }*/

    }

   function _attemptTransferFrom(address _NFTAddress, uint256 _tokenId, address _recipient) internal returns (bool) {

        _NFTAddress.call(abi.encodeWithSelector(IERC721(_NFTAddress).approve.selector, address(this), _tokenId));
        (bool success, ) = _NFTAddress.call(abi.encodeWithSelector(IERC721(_NFTAddress).transferFrom.selector, address(this), _recipient, _tokenId));
        return success;
        
    }

    /*function _attemptTransfer(address _NFTAddress, uint256 _tokenId, address _recipient) internal returns (bool) {
        (bool success, ) = _NFTAddress.call(abi.encodeWithSelector(IERC721(_NFTAddress).transfer.selector, _recipient, _tokenId));
        return success;
    }*/

function _transferNFT(address _NFTAddress, uint256 _tokenId, address _recipient) internal returns (bool) {

    IERC721(_NFTAddress).transferFrom(address(this), _recipient, _tokenId);

}

}////



